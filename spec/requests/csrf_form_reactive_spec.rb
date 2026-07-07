# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

# Issue #42 regression: a reactive component whose view_template renders a Rails
# form with a CSRF token (`form_authenticity_token`) crashed with
# `NoMethodError: undefined method 'env' for nil` on 0.4.0, because the re-render
# went through a REQUEST-LESS view context. This drives the real action endpoint
# (the path the reporter hit) — re-rendering CsrfFormComponent must succeed.
RSpec.describe "Reactive action re-rendering a CSRF form (issue #42)", type: :request do
  include Turbo::Broadcastable::TestHelper

  let(:todo) { Todo.create!(title: "before", done: false) }

  it "re-renders the form component without crashing on form_authenticity_token" do
    post_action(CsrfFormComponent, payload: { "gid" => todo.to_gid.to_s },
      act: "save", params: { title: "after" })

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('name="authenticity_token"')
    expect(response.body).to include("after")
  end

  it "rolls the signed identity token forward in the replace stream" do
    post_action(CsrfFormComponent, payload: { "gid" => todo.to_gid.to_s },
      act: "save", params: { title: "after" })

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-reactive-token-value=")
  end

  # The broadcast path is where the off-request render matters most (renders
  # once per broadcast call, no HTTP request on the stack). A broadcast of a
  # CSRF-form component must render through the request-bound context too.
  it "broadcasts the CSRF form component without crashing" do
    broadcasts = capture_turbo_stream_broadcasts(todo) do
      CsrfFormComponent.broadcast_to(todo, replace: todo)
    end

    html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
    expect(html).to include('name="authenticity_token"')
    expect(html).to include('action="replace"')
  end
end
