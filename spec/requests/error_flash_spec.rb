# frozen_string_literal: true

require "rails_helper"

# Issue #100: Phlex::Reactive.error_flash — a server-rendered, user-visible flash
# on every endpoint rescue path (400/403/404). The contract:
#
#   * Default nil = today's behavior (bare head / verbose plain-text diagnostic).
#   * When set (a lambda ->(kind) { "message" }), the rescue path ALSO renders a
#     turbo-stream flash into Phlex::Reactive.flash_target — WITH THE SAME STATUS
#     it returns today. Statuses NEVER change with the flag.
#   * The lambda receives the failure KIND (:tampered/:forbidden/:not_found/…).
#   * Composes with verbose_errors: the turbo-stream flash wins the RESPONSE BODY
#     (a plain-text diagnostic and a turbo-stream flash can't both be the body);
#     the diagnostic still goes to the log.
RSpec.describe "error_flash — user-visible endpoint failures (issue #100)", type: :request do
  # Restore both flags after each example so a set lambda / explicit flag never
  # leaks into the next spec.
  around do
    it.run
  ensure
    Phlex::Reactive.error_flash = nil
    if Phlex::Reactive.instance_variable_defined?(:@verbose_errors)
      Phlex::Reactive.remove_instance_variable(:@verbose_errors)
    end
  end

  before { allow(Rails.logger).to receive(:warn).and_call_original }

  let!(:todo) { Todo.create!(title: "x", done: false) }

  def post_raw(token:, act: "toggle", params: {})
    post "/reactive/actions",
      params: { token:, act:, params: }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }
  end

  describe "the config default" do
    it "defaults to nil (no flash)" do
      expect(Phlex::Reactive.error_flash).to be_nil
    end
  end

  describe "when error_flash is nil (default behavior unchanged)" do
    it "a tampered token keeps the 400 with no flash stream" do
      Phlex::Reactive.verbose_errors = false
      post_raw(token: "not.a.real.token")

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to be_empty
      expect(response.body).not_to include("reactive-flash")
    end
  end

  describe "when error_flash is set" do
    before { Phlex::Reactive.error_flash = -> { "Something went wrong (#{it})" } }

    it "renders a turbo-stream flash at the SAME 400 for a tampered token" do
      post_raw(token: "not.a.real.token")

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="flash"')
      expect(response.body).to include("reactive-flash--error")
      expect(response.body).to include("Something went wrong (tampered)")
    end

    it "renders a turbo-stream flash at the SAME 403 for an undeclared action" do
      post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "togle")

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("reactive-flash--error")
      expect(response.body).to include("(forbidden)")
    end

    it "renders a turbo-stream flash at the SAME 404 for a missing record" do
      gid = todo.to_gid.to_s
      todo.destroy!
      post_action(TodoItemComponent, payload: { "gid" => gid }, act: "toggle")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("reactive-flash--error")
      expect(response.body).to include("(not_found)")
    end

    it "passes the correct kind to the lambda per rescue path" do
      kinds = []
      Phlex::Reactive.error_flash = lambda {
        kinds << it
        "msg"
      }

      post_raw(token: "bad")
      post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "togle")

      expect(kinds).to eq(%i[tampered forbidden])
    end

    it "the flash body HTML-escapes the lambda's message (injection contract)" do
      Phlex::Reactive.error_flash = ->(_kind) { "<script>alert(1)</script>" }
      post_raw(token: "bad")

      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(response.body).to include("&lt;script&gt;")
    end

    it "still fires the endpoint warn log (server-side debuggability preserved)" do
      post_raw(token: "not.a.real.token")

      expect(Rails.logger).to have_received(:warn)
        .with(a_string_including("[phlex-reactive]", "token signature invalid"))
    end
  end

  describe "composing with verbose_errors" do
    before do
      Phlex::Reactive.verbose_errors = true
      Phlex::Reactive.error_flash = -> { "flash for #{it}" }
    end

    it "the turbo-stream flash wins the response body over the plain-text diagnostic" do
      post_raw(token: "not.a.real.token")

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("reactive-flash--error")
      expect(response.body).to include("flash for tampered")
      # The diagnostic is NOT the body (a turbo-stream flash and a plain-text
      # diagnostic can't both be the response) — it goes to the log instead.
      expect(response.body).not_to include("secret_key_base mismatch")
    end

    it "still logs the verbose diagnostic even though the flash owns the body" do
      post_raw(token: "not.a.real.token")

      expect(Rails.logger).to have_received(:warn)
        .with(a_string_including("[phlex-reactive]", "token signature invalid"))
    end
  end

  # A flash lambda that itself raises must not blow up the endpoint or change the
  # status — degrade gracefully to the non-flash body (the invariant: a failure
  # surface should never turn one failure into a worse one).
  describe "when the error_flash lambda raises" do
    before do
      Phlex::Reactive.verbose_errors = false
      Phlex::Reactive.error_flash = ->(_kind) { raise "boom in flash" }
    end

    it "falls back to the status-only body and keeps the status" do
      post_raw(token: "not.a.real.token")

      expect(response).to have_http_status(:bad_request)
      expect(response.body).not_to include("reactive-flash")
    end
  end
end
