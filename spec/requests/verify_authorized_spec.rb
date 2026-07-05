# frozen_string_literal: true

require "rails_helper"

# verify_authorized (issue #168): the default-ON runtime guard. An action that
# completes WITHOUT any authorization call raises AuthorizationNotVerified INSIDE
# the transaction — so the mutation ROLLS BACK (fail-closed, stronger than
# Pundit's after-the-fact check). This request spec drives the real endpoint with
# the feature re-enabled (the dummy sets verify_authorized = false globally),
# proving every path: violation → raise + rollback, an intercepted authorize!,
# mark_authorized!, class/per-action skip, the global off switch, and that a
# genuine denial still 403s through authorization_errors.
RSpec.describe "verify_authorized enforcement (issue #168)", type: :request do
  # The dummy disables the guard globally (it has no authz layer). Re-enable it
  # around these examples, then RESTORE the dummy's configured value — not the
  # lazy default — so a later request spec that relies on the global-off setting
  # isn't tripped by this suite (removing the ivar would re-default it to true).
  around do
    previous = Phlex::Reactive.verify_authorized
    Phlex::Reactive.verify_authorized = true
    it.run
  ensure
    Phlex::Reactive.verify_authorized = previous
  end

  def capture_action_events
    events = []
    sub = ActiveSupport::Notifications.subscribe("action.phlex_reactive") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  describe "an action that authorizes (intercepted authorize!)" do
    it "returns 200 — the authorization call marked the tracking cell" do
      todo = Todo.create!(title: "orig")
      post_action(AuthorizedTodoComponent, act: "rename",
        payload: { "gid" => todo.to_gid.to_s }, params: { title: "renamed" })
      expect(response).to have_http_status(:ok)
      expect(todo.reload.title).to eq("renamed")
    end
  end

  describe "an action that uses mark_authorized! (bespoke check)" do
    it "returns 200 — the manual mark satisfies the guard" do
      todo = Todo.create!(title: "orig")
      post_action(AuthorizedTodoComponent, act: "rename_marked",
        payload: { "gid" => todo.to_gid.to_s }, params: { title: "manual" })
      expect(response).to have_http_status(:ok)
      expect(todo.reload.title).to eq("manual")
    end
  end

  describe "an action that never authorizes (the violation)" do
    it "raises AuthorizationNotVerified" do
      todo = Todo.create!(title: "orig")
      expect do
        post_action(AuthorizedTodoComponent, act: "rename_unguarded",
          payload: { "gid" => todo.to_gid.to_s }, params: { title: "sneaky" })
      end.to raise_error(Phlex::Reactive::AuthorizationNotVerified, /rename_unguarded/)
    end

    it "ROLLS BACK the mutation the unguarded action performed" do
      todo = Todo.create!(title: "orig")
      begin
        post_action(AuthorizedTodoComponent, act: "rename_unguarded",
          payload: { "gid" => todo.to_gid.to_s }, params: { title: "sneaky" })
      rescue Phlex::Reactive::AuthorizationNotVerified
        # expected — the raise fires inside the transaction
      end
      # Fail-closed: the update! inside the action must NOT have committed.
      expect(todo.reload.title).to eq("orig")
    end

    it "tags the action.phlex_reactive event outcome :unverified and re-raises" do
      todo = Todo.create!(title: "orig")
      events = capture_action_events do
        post_action(AuthorizedTodoComponent, act: "rename_unguarded",
          payload: { "gid" => todo.to_gid.to_s }, params: { title: "sneaky" })
      rescue Phlex::Reactive::AuthorizationNotVerified
        # swallow so we can inspect the emitted event
      end
      expect(events.first.payload[:outcome]).to eq(:unverified)
    end
  end

  describe "skip_verify_authorized" do
    it "returns 200 for a whole-component skip (public, no authz)" do
      post_action(PublicCounterComponent, act: "increment", payload: { "s" => { "count" => 1 } })
      expect(response).to have_http_status(:ok)
    end

    it "returns 200 for a per-action skip" do
      todo = Todo.create!(title: "orig")
      post_action(AuthorizedTodoComponent, act: "rename_skipped",
        payload: { "gid" => todo.to_gid.to_s }, params: { title: "skipped" })
      expect(response).to have_http_status(:ok)
      expect(todo.reload.title).to eq("skipped")
    end
  end

  describe "the global off switch" do
    it "returns 200 for an unguarded action when verify_authorized is false" do
      Phlex::Reactive.verify_authorized = false
      todo = Todo.create!(title: "orig")
      post_action(AuthorizedTodoComponent, act: "rename_unguarded",
        payload: { "gid" => todo.to_gid.to_s }, params: { title: "allowed" })
      expect(response).to have_http_status(:ok)
      expect(todo.reload.title).to eq("allowed")
    end
  end

  describe "a genuine denial still 403s (authorization_errors is unchanged)" do
    it "maps a registered authorization error to 403, not the verify guard" do
      todo = Todo.create!(title: "orig")
      post_action(AuthorizedTodoComponent, act: "rename_denied",
        payload: { "gid" => todo.to_gid.to_s }, params: { title: "nope" })
      expect(response).to have_http_status(:forbidden)
      # The denial raised (and marked nothing) — the mutation never happened.
      expect(todo.reload.title).to eq("orig")
    end
  end
end
