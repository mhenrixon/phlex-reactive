# frozen_string_literal: true

require "system_helper"

RSpec.describe "Todos (record-backed reactive components)", type: :system do
  it "adds, toggles, and renames todos" do
    Todo.create!(title: "existing task")

    visit "/todos"
    expect(page).to have_css("[data-testid='todo']", count: 1)
    expect(page).to have_field(with: "existing task")

    # Add (target the new-todo input specifically; the existing row also has a
    # name="title" input for inline rename)
    find("[data-testid='new-todo']").set("buy oat milk")
    find("[data-testid='add']").click
    expect(page).to have_css("[data-testid='todo']", count: 2)
    expect(page).to have_field(with: "buy oat milk")
    expect(Todo.count).to eq(2)

    # Toggle the first todo
    within first("[data-testid='todo']") do
      find("[data-testid='toggle']").click
    end
    expect(page).to have_css("[data-testid='todo'][data-done='true']", count: 1)
  end

  it "persists a rename via the change event" do
    todo = Todo.create!(title: "old name")
    visit "/todos"

    field = find("##{ActionView::RecordIdentifier.dom_id(todo)} input[name='title']")
    field.set("new name")
    field.native.evaluate("el => el.blur()") # fire change

    expect(page).to have_field(with: "new name")
    expect(todo.reload.title).to eq("new name")
  end
end
