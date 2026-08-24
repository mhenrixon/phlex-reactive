# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

# Issue #232: components rendered in an ACTOR REPLY go through the memoized
# off-request view context, whose url_options are process defaults — so any
# absolute URL helper (image_tag on an Active Storage attachment being the
# everyday case) renders the WRONG host on a multi-host app. The fix threads
# the request's protocol/host/port into the reply render (the
# ActiveStorage::SetCurrent move). Broadcasts stay on process defaults — there
# is no request, and subscribers can be on different hosts.
RSpec.describe "Reply url_options (issue #232)", type: :request do
  include Turbo::Broadcastable::TestHelper

  def reply_link_href
    response.body[/data-testid="abs-link"[^>]*href="([^"]+)"/, 1] ||
      response.body[/href="([^"]+)"[^>]*data-testid="abs-link"/, 1]
  end

  describe "the actor reply (POST action_path)" do
    it "renders absolute URLs with the REQUEST's host, not the process default" do
      host! "yoga.test"
      post_action(SettingsLinkComponent, payload: { "s" => { "saved" => false } }, act: "save")

      expect(response).to have_http_status(:ok)
      expect(reply_link_href).to eq("http://yoga.test/counter")
    end

    it "carries the request's port and protocol" do
      token = token_for(SettingsLinkComponent, { "s" => { "saved" => false } })
      post Phlex::Reactive.action_path,
        params: { token:, act: "save", params: {} }.to_json,
        headers: { "Content-Type" => "application/json",
                   "Accept" => "text/vnd.turbo-stream.html",
                   "Host" => "yoga.local:1120" }

      expect(response).to have_http_status(:ok)
      expect(reply_link_href).to eq("http://yoga.local:1120/counter")
    end
  end

  describe "a broadcast fired INSIDE the action" do
    it "keeps the process-default url_options (never the actor's host)" do
      host! "yoga.test"
      broadcasts = capture_turbo_stream_broadcasts("settings") do
        post_action(SettingsLinkComponent, payload: { "s" => { "saved" => false } }, act: "save_and_broadcast")
      end

      expect(response).to have_http_status(:ok)
      # The actor's own reply carries the actor host…
      expect(reply_link_href).to eq("http://yoga.test/counter")

      # …but the broadcast render must NOT: subscribers can be on other hosts.
      broadcast_href = broadcasts.sole.to_html[/href="([^"]+)"/, 1]
      expect(broadcast_href).to start_with("http://example.org")
      expect(broadcast_href).not_to include("yoga.test")
    end
  end

  describe "the defer pull endpoint (POST defer_path)" do
    it "renders the deferred segment with the request's host (it IS an actor request)" do
      host! "yoga.test"
      token = Phlex::Reactive.sign_defer({ "c" => "SettingsLinkComponent", "s" => { "saved" => true } })
      post Phlex::Reactive.defer_path,
        params: { token: }.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(reply_link_href).to eq("http://yoga.test/counter")
    end
  end

  describe "off-request renders (no actor)" do
    it "keeps process-default url_options for a plain broadcast" do
      broadcasts = capture_turbo_stream_broadcasts("settings") do
        SettingsLinkComponent.broadcast_to("settings", replace: SettingsLinkComponent.new(saved: true))
      end

      expect(broadcasts.sole.to_html[/href="([^"]+)"/, 1]).to start_with("http://example.org")
    end
  end
end
