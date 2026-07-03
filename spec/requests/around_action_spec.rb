# frozen_string_literal: true

require "rails_helper"

# Component-aware around_action seam (issue #112). A wrapper stack folded into
# the endpoint BETWEEN with_connection_id and transaction_wrapper — so a wrapper
# sees the resolved component instance, the declared action name, and the coerced
# params, and a rejection never opens a transaction. Distinct from the
# base-controller seam (HTTP-layer: auth/CSRF/coarse rate limiting), which never
# sees the resolved action.
RSpec.describe "Phlex::Reactive.around_action", type: :request do
  # The stack is process-global config; reset it around every example so one
  # spec's wrapper never leaks into another (the shipped test-isolation hook).
  around do
    Phlex::Reactive.reset_around_actions!
    it.run
    Phlex::Reactive.reset_around_actions!
  end

  describe "the empty stack (default hot path)" do
    it "is byte-identical to no wrapper — a plain increment still replaces self" do
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "increment")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"')
      expect(response.body).to include('target="counter"')
      expect(response.body).to match(/>\s*2\s*</) # 1 -> 2
    end
  end

  describe "the context the wrapper sees" do
    it "carries the resolved component instance, the action name, the coerced params, and the request" do
      seen = {}
      Phlex::Reactive.around_action do |ctx, &action|
        seen[:component]   = ctx.component
        seen[:action_name] = ctx.action_name
        seen[:params]      = ctx.params
        seen[:request]     = ctx.request
        action.call
      end

      post_action(CounterComponent, payload: { "s" => { "count" => 9 } }, act: "set", params: { count: "3" })

      expect(response).to have_http_status(:ok)
      expect(seen[:component]).to be_a(CounterComponent)
      expect(seen[:action_name]).to eq(:set)
      # Coerced, not raw: "3" (string on the wire) has been cast to Integer 3 by
      # the schema before the fold runs.
      expect(seen[:params]).to eq({ count: 3 })
      expect(seen[:request]).to respond_to(:remote_ip)
    end

    it "freezes the context (a wrapper cannot widen invokability by mutating it)" do
      frozen = nil
      Phlex::Reactive.around_action do |ctx, &action|
        frozen = ctx.frozen?
        action.call
      end

      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "increment")

      expect(frozen).to be(true)
    end
  end

  describe "the return-value contract (issue #112 — a wrapper MUST return the continuation)" do
    it "lets a Phlex::Reactive::Response survive the stack (remove is honored, not downgraded to a replace)" do
      todo = Todo.create!(title: "moderate me", done: false)

      # A well-behaved wrapper: it returns action.call's value, so the action's
      # Response.remove reaches response_streams unchanged.
      Phlex::Reactive.around_action do |_ctx, &action|
        result = action.call
        result
      end

      post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "archive")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="remove"')
      expect(response.body).not_to include('action="replace"')
    end

    it "downgrades to the implicit self-replace when a wrapper swallows the return value (the documented footgun)" do
      # A MISBEHAVING wrapper: it returns its own trailing value (a truthy log
      # line), not action.call's. response_streams sees a non-Response and falls
      # back to the implicit single replace — proving the contract is real.
      Phlex::Reactive.around_action do |_ctx, &action|
        action.call
        "logged" # <- WRONG: not the continuation's value
      end

      todo = Todo.create!(title: "moderate me", done: false)
      post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "archive")

      expect(response).to have_http_status(:ok)
      # The Response.remove was dropped; the endpoint fell back to a self replace.
      expect(response.body).to include('action="replace"')
      expect(response.body).not_to include('action="remove"')
    end
  end

  describe "the fold sits OUTSIDE the transaction (a rejection opens no transaction)" do
    it "leaves no DB write when a wrapper raises BEFORE calling the continuation" do
      todo = Todo.create!(title: "keep me", done: false)

      Phlex::Reactive.around_action do |_ctx, &_action|
        raise CounterComponent::Denied, "rate limited before the action ran"
      end

      expect do
        post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "toggle")
      end.not_to(change { todo.reload.done? })

      # The registered error maps to 403, and the action never ran — no toggle.
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "error mapping" do
    it "maps a wrapper raising a registered authorization error to 403" do
      Phlex::Reactive.around_action do |_ctx, &_action|
        raise CounterComponent::Denied, "denied in the wrapper"
      end

      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "increment")

      expect(response).to have_http_status(:forbidden)
    end

    it "lets an UNREGISTERED wrapper error surface as a 500 (same as today)" do
      Phlex::Reactive.around_action do |_ctx, &_action|
        raise "unregistered boom"
      end

      expect do
        post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "increment")
      end.to raise_error("unregistered boom")
    end
  end

  describe "multiple wrappers nest LIFO (the stack folds outermost-first)" do
    it "runs the last-registered wrapper OUTERMOST around the earlier ones" do
      order = []
      Phlex::Reactive.around_action do |_ctx, &action|
        order << :first_before
        result = action.call
        order << :first_after
        result
      end
      Phlex::Reactive.around_action do |_ctx, &action|
        order << :second_before
        result = action.call
        order << :second_after
        result
      end

      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "increment")

      expect(response).to have_http_status(:ok)
      # Registration appends; folding wraps so the LAST-registered runs OUTERMOST.
      expect(order).to eq(%i[second_before first_before first_after second_after])
    end
  end
end
