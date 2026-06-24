# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe "Reactive actions", type: :request do
  include Turbo::Broadcastable::TestHelper

  # Mint a token exactly as a component would, using the app's verifier.
  def token_for(klass, payload)
    Phlex::Reactive.sign(payload.merge("c" => klass.name))
  end

  def post_action(klass, payload:, act:, params: {})
    post "/reactive/actions",
      params: {token: token_for(klass, payload), act:, params:}.to_json,
      headers: {"Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html"}
  end

  describe "state-backed component (CounterComponent)" do
    it "runs an action and returns an auto-targeted turbo-stream" do
      post_action(CounterComponent, payload: {"s" => {"count" => 1}}, act: "increment")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="replace"')
      expect(response.body).to include('target="counter"')
      expect(response.body).to match(/>\s*2\s*</) # 1 -> 2
    end

    it "coerces a typed param" do
      post_action(CounterComponent, payload: {"s" => {"count" => 9}}, act: "set", params: {count: "0"})
      expect(response.body).to match(/>\s*0\s*</)
    end

    it "forbids an undeclared action (default-deny)" do
      post_action(CounterComponent, payload: {"s" => {"count" => 1}}, act: "destroy_everything")
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "record-backed component (TodoItemComponent)" do
    let!(:todo) { Todo.create!(title: "write specs", done: false) }

    it "re-finds the record by GlobalID and runs the action" do
      post_action(TodoItemComponent, payload: {"gid" => todo.to_gid.to_s}, act: "toggle")

      expect(response).to have_http_status(:ok)
      expect(todo.reload.done?).to be(true)
      expect(response.body).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "returns 404 when the record no longer exists" do
      gid = todo.to_gid.to_s
      todo.destroy!
      post_action(TodoItemComponent, payload: {"gid" => gid}, act: "toggle")
      expect(response).to have_http_status(:not_found)
    end

    # Regression for issue #4: the action endpoint builds via reactive_record_key
    # (:todo) while the broadcast path used the demodulized class name
    # (:todo_item_component) — so the broadcast raised
    # `ArgumentError: missing keyword: :todo`. The component class name
    # (TodoItemComponent) differs from its reactive_record name (:todo), and it
    # carries no model_param_name override, so both paths must now agree.
    it "broadcasts a replace without raising ArgumentError (issue #4)" do
      stream = "todos"

      expect {
        broadcasts = capture_turbo_stream_broadcasts(stream) do
          TodoItemComponent.broadcast_replace_to(stream, model: todo)
        end

        html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
        expect(html).to include('action="replace"')
        expect(html).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
        expect(html).to include("write specs")
      }.not_to raise_error
    end
  end

  describe "record + state component (InlineEditComponent, issue #6)" do
    let!(:todo) { Todo.create!(title: "original", done: false) }

    # Mint a token exactly as the component would after a render: it signs the
    # record gid AND the declared state (attribute, editing).
    def state_payload(attribute:, editing:)
      {"gid" => todo.to_gid.to_s, "s" => {"attribute" => attribute.to_s, "editing" => editing}}
    end

    it "restores the signed state so the mode survives an action" do
      # We are in edit mode (editing: true was signed by the prior render). The
      # endpoint must rebuild WITH editing: true — not the initialize default.
      post_action(InlineEditComponent,
        payload: state_payload(attribute: :title, editing: true),
        act: "cancel")

      expect(response).to have_http_status(:ok)
      # cancel flips editing -> false, so the response renders display mode.
      expect(response.body).to include('data-testid="display"')
    end

    it "save writes the SIGNED attribute, not a nil/blank column" do
      post_action(InlineEditComponent,
        payload: state_payload(attribute: :title, editing: true),
        act: "save",
        params: {value: "renamed"})

      expect(response).to have_http_status(:ok)
      expect(todo.reload.title).to eq("renamed") # the correct column, not nil
      expect(response.body).to include("renamed")
    end

    it "edit flips into edit mode and re-renders the input" do
      post_action(InlineEditComponent,
        payload: state_payload(attribute: :title, editing: false),
        act: "edit")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="field"')
      expect(response.body).to include('value="original"') # the signed attribute's value
    end

    it "rejects a token whose signed attribute was tampered" do
      token = token_for(InlineEditComponent, state_payload(attribute: :title, editing: true))
      # Re-encode the payload to switch the editable column onto the original
      # signature — verification must fail (the digest no longer matches).
      data, sig = token.split("--", 2)
      decoded = JSON.parse(Base64.urlsafe_decode64(data))
      decoded["_rails"]["data"]["s"]["attribute"] = "done"
      forged = "#{Base64.urlsafe_encode64(decoded.to_json, padding: false)}--#{sig}"

      post "/reactive/actions",
        params: {token: forged, act: "save", params: {value: "x"}}.to_json,
        headers: {"Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html"}

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "blank field reaches the action; the component guards (issue #8)" do
    # The transport doesn't second-guess values: a genuinely-cleared field is
    # sent as "" and reaches the action. Protecting the record from a blank
    # write is the action's job (`if title.present?`), not the transport's. The
    # issue #8 fix is about COLLECTING the right value from rich-text/custom
    # editors in the first place — covered by spec/system/rich_editor_spec.rb.
    let!(:todo) { Todo.create!(title: "keep me", done: false) }

    it "passes an explicitly blank param through to the guarded action" do
      post_action(TodoItemComponent, payload: {"gid" => todo.to_gid.to_s}, act: "rename", params: {title: ""})

      expect(response).to have_http_status(:ok)
      expect(todo.reload.title).to eq("keep me") # unchanged: guarded by `if title.present?`
    end
  end

  describe "tampering" do
    it "rejects a forged token" do
      post "/reactive/actions",
        params: {token: "not.a.real.token", act: "increment"}.to_json,
        headers: {"Content-Type" => "application/json"}
      expect(response).to have_http_status(:bad_request)
    end
  end
end
