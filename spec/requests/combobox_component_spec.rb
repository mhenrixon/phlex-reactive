# frozen_string_literal: true

require "rails_helper"

# The combobox exercises client-side list navigation (issue #72): the search
# input carries the listnav keyboard wiring, and `select` is a normal signed
# reactive action (the keyboard just clicks an option's trigger).
RSpec.describe "ComboboxComponent", type: :request do
  describe "render at /combobox" do
    before { get "/combobox" }

    it "wires the search input to dispatch + the listnav keyboard filters" do
      expect(response).to have_http_status(:ok)
      body = CGI.unescapeHTML(response.body)
      expect(body).to include("input->reactive#dispatch")
      expect(body).to include("keydown.down->reactive#listnavNext")
      expect(body).to include("keydown.up->reactive#listnavPrev")
      expect(body).to include("keydown.enter->reactive#listnavPick")
      expect(body).to include("keydown.esc->reactive#listnavClose")
    end

    it "emits the option selector so the controller can find the options" do
      expect(response.body).to include('data-reactive-listnav-option-param="[role=option]"')
    end
  end

  describe "the select action (signed, server-side — the keyboard just clicks it)" do
    it "records a valid selection and morphs" do
      post_action(ComboboxComponent, payload: { "s" => { "query" => "ap", "selected" => nil } },
        act: "select", params: { name: "Apple" })
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('method="morph"')
      expect(CGI.unescapeHTML(response.body)).to include("Selected: Apple")
    end

    it "ignores a forged option not in the list (no trusting client input)" do
      post_action(ComboboxComponent, payload: { "s" => { "query" => "x", "selected" => nil } },
        act: "select", params: { name: "DROP TABLE" })
      expect(response.body).not_to include("Selected: DROP TABLE")
    end

    it "forbids an undeclared action (default-deny)" do
      post_action(ComboboxComponent, payload: { "s" => { "query" => "", "selected" => nil } }, act: "obliterate")
      expect(response).to have_http_status(:forbidden)
    end
  end
end
