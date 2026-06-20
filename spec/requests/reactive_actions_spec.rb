# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reactive actions", type: :request do
  # Mint a token exactly as a component would, using the app's verifier.
  def token_for(klass, payload)
    Phlex::Reactive.sign(payload.merge("c" => klass.name))
  end

  def post_action(klass, payload:, act:, params: {})
    post "/reactive/actions",
      params: { token: token_for(klass, payload), act:, params: }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }
  end

  describe "state-backed component (CounterComponent)" do
    it "runs an action and returns an auto-targeted turbo-stream" do
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "increment")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="replace"')
      expect(response.body).to include('target="counter"')
      expect(response.body).to match(/>\s*2\s*</) # 1 -> 2
    end

    it "coerces a typed param" do
      post_action(CounterComponent, payload: { "s" => { "count" => 9 } }, act: "set", params: { count: "0" })
      expect(response.body).to match(/>\s*0\s*</)
    end

    it "forbids an undeclared action (default-deny)" do
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "destroy_everything")
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "record-backed component (TodoItemComponent)" do
    let!(:todo) { Todo.create!(title: "write specs", done: false) }

    it "re-finds the record by GlobalID and runs the action" do
      post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "toggle")

      expect(response).to have_http_status(:ok)
      expect(todo.reload.done?).to be(true)
      expect(response.body).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "returns 404 when the record no longer exists" do
      gid = todo.to_gid.to_s
      todo.destroy!
      post_action(TodoItemComponent, payload: { "gid" => gid }, act: "toggle")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "tampering" do
    it "rejects a forged token" do
      post "/reactive/actions",
        params: { token: "not.a.real.token", act: "increment" }.to_json,
        headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:bad_request)
    end
  end
end
