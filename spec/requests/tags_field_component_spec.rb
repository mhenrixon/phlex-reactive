# frozen_string_literal: true

require "rails_helper"

# The tag-chip input (issue #203) — a CLIENT-ONLY page (ClientBindings: no
# token, no actions), so the request layer proves the WIRE: the root binds the
# hidden field, the query input composes listnav BEFORE tagsAdd (Enter prefers
# the highlighted option), each suggestion is a tagsPick trigger, the chip
# template ships server-owned markup, and the GET submit-back echoes the
# comma-joined value (the server-side half of the round trip).
RSpec.describe "TagsFieldComponent", type: :request do
  describe "render at /tags_field" do
    before { get "/tags_field?tags=Ruby,Rails" }

    it "binds the root to the hidden comma-joined field (token-less)" do
      expect(response).to have_http_status(:ok)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include('data-reactive-tags-field="[name="tags"]"')
      expect(body).to include('name="tags" value="Ruby,Rails"')
      expect(response.body).not_to include("data-reactive-token-value")
    end

    it "orders Enter handling listnav-first so a highlighted option wins over free text" do
      body = CGI.unescapeHTML(response.body)
      expect(body).to include(
        "keydown.enter->reactive#listnavPick keydown.esc->reactive#listnavClose keydown.enter->reactive#tagsAdd"
      )
    end

    it "renders each suggestion as a client-only tagsPick option with its declared tag" do
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("click->reactive#tagsPick")
      expect(body).to include('data-reactive-tag-param="Postgres"')
      expect(body).not_to include("reactive#dispatch") # nothing here POSTs
    end

    it "ships the server-owned chip template and the server-rendered initial chips" do
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("data-reactive-tags-template")
      expect(body).to include("data-reactive-tags-list")
      expect(body).to include('data-reactive-tag="Ruby"')
      expect(body).to include("click->reactive#tagsRemove")
    end

    it "echoes the submitted comma-joined value (the server received the form state)" do
      expect(CGI.unescapeHTML(response.body)).to include("Saved: Ruby,Rails")
    end
  end

  describe "first visit (no tags param)" do
    it "renders empty: no chips, no echo" do
      get "/tags_field"
      expect(response).to have_http_status(:ok)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include('name="tags" value=""')
      expect(body).not_to include("Saved:")
    end
  end
end
