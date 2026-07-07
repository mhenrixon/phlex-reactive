# frozen_string_literal: true

require "rails_helper"

# Issue #184: reactive_scope resolves the field wire name AND the param unwrap.
# A scoped component's fields POST bracketed (todo[title]); the endpoint unwraps
# exactly ONE scope level before schema matching, so a FLAT schema
# { title: :string } matches — the #67 bracket-drop footgun, fixed.
RSpec.describe "ScopedEditorComponent (issue #184 — scoped fields + param unwrap)", type: :request do
  let!(:todo) { Todo.create!(title: "old") }

  it "renders the field with the scope-prefixed wire name" do
    component = ScopedEditorComponent.new(todo:)
    html = Phlex::Reactive.render(component)
    expect(html).to include('name="todo[title]"')
    expect(html).to include('data-reactive-scope="todo"')
  end

  it "unwraps one scope level so a flat schema matches the bracketed POST" do
    # The client POSTs the bracketed shape Rails expands to { "todo" => { "title" => … } }.
    post_action(ScopedEditorComponent, act: "save",
      payload: { "gid" => todo.to_gid.to_s },
      params: { "todo" => { "title" => "renamed" } })

    expect(response).to have_http_status(:ok)
    expect(todo.reload.title).to eq("renamed") # the flat save(title:) received it
  end

  it "drops an unknown param inside the scope (no raw mass assignment)" do
    post_action(ScopedEditorComponent, act: "save",
      payload: { "gid" => todo.to_gid.to_s },
      params: { "todo" => { "title" => "ok", "evil" => "x" } })

    expect(response).to have_http_status(:ok)
    expect(todo.reload.title).to eq("ok") # title coerced; evil dropped by the schema
  end
end
