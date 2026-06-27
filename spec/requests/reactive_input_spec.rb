# frozen_string_literal: true

require "rails_helper"

# Issue #23: reactive_input/reactive_select emit the action-param `name`
# binding, so the value travels with the action without a hand-written
# `name: "value"` magic string. We assert BOTH the rendered markup carries the
# right name AND the action actually receives the bound param end-to-end.
RSpec.describe "reactive_input / reactive_select binding (issue #23)", type: :request do
  def token_for(klass, payload)
    Phlex::Reactive.sign(payload.merge("c" => klass.name))
  end

  def post_action(klass, payload:, act:, params: {})
    post "/reactive/actions",
      params: {token: token_for(klass, payload), act:, params:}.to_json,
      headers: {"Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html"}
  end

  let!(:todo) { Todo.create!(title: "before", done: false) }
  let(:payload) { {"gid" => todo.to_gid.to_s, "s" => {"attribute" => "title"}} }

  it "renders an input whose name is the bound param (not a magic string)" do
    html = Phlex::Reactive.render(ReactiveInputComponent.new(record: todo, attribute: :title))

    expect(html).to include('name="value"')
    expect(html).to include('value="before"')
  end

  it "renders a select bound to the param with the option block as content" do
    html = Phlex::Reactive.render(ReactiveInputComponent.new(record: todo, attribute: :title))

    expect(html).to match(/<select[^>]*name="status"/)
    expect(html).to include("<option")
    expect(html).to include(">open<")
  end

  it "delivers the bound value to the action end-to-end" do
    post_action(ReactiveInputComponent, payload:, act: "save", params: {value: "after"})

    expect(response).to have_http_status(:ok)
    expect(todo.reload.title).to eq("after")
  end
end
