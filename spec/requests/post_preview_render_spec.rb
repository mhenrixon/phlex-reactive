# frozen_string_literal: true

require "rails_helper"

# Renders PostPreviewComponent through a real request (issue #104) and pins the
# typed-compute wire + the reactive_text mirrors: the inputs param is a JSON
# OBJECT of name→type, the preview heading and counter are data-reactive-text
# nodes seeded with the server's derived value, and the mirrors carry NO `name`
# attribute (so they're never collected/POSTed as params).
RSpec.describe "PostPreviewComponent render (reactive_text + typed compute)", type: :request do
  let(:todo) { Todo.create!(title: "Draft") }

  before { get "/post_preview/#{todo.id}" }

  it "renders the compute binding with a TYPED inputs object (name→type)" do
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-reactive-compute-reducer-param="preview"')
    # The hash form emits a JSON object; HTML-escaped in the attribute.
    inputs = response.body[/data-reactive-compute-inputs-param="([^"]*)"/, 1]
    expect(JSON.parse(CGI.unescapeHTML(inputs))).to eq("title" => "string")
  end

  it "seeds the preview heading + counter from the server's derived value" do
    expect(response.body).to include('data-reactive-text="title"')
    expect(response.body).to include('data-reactive-text="char_count"')
    # "Draft" = 5 chars — the server twin seeds the same string the reducer would.
    expect(response.body).to match(%r{data-reactive-text="char_count"[^>]*>5/80<})
  end

  it "gives the reactive_text mirrors NO name attribute (never collected as params)" do
    # reactive_text renders a <span data-reactive-text=…> — the mirror must carry
    # no name= (only the real <input> does), or #collectFields would sweep it in.
    title_span = response.body[/<span[^>]*data-reactive-text="title"[^>]*>/]
    expect(title_span).to be_present
    expect(title_span).not_to include("name=")
    count_span = response.body[/<span[^>]*data-reactive-text="char_count"[^>]*>/]
    expect(count_span).to be_present
    expect(count_span).not_to include("name=")
  end

  it "wires the title field to the client recompute mirror (input), plus a save action" do
    expect(response.body).to include("input-&gt;reactive#recompute").or include("input->reactive#recompute")
    expect(response.body).to include("save")
  end
end
