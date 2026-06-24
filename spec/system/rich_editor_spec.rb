# frozen_string_literal: true

require "system_helper"

# Issue #8: a reactive `save` must collect named rich-text / custom-editor
# fields (lexxy-editor, trix-editor, [contenteditable]) — not just
# input/select/textarea. We stand in for a custom editor with a named
# [contenteditable] element. Before the fix its value was dropped and the
# record was silently wiped.
RSpec.describe "Rich editor field collection (issue #8)", type: :system do
  it "collects a named contenteditable value on a reactive save" do
    todo = Todo.create!(title: "before")
    visit "/rich_editor/#{todo.id}"

    editor = find("[data-testid='editor']")
    # Replace the editable content with new text (contenteditable, not an input).
    editor.native.evaluate('el => { el.textContent = "after edit" }')

    find("[data-testid='save']").click

    # The re-rendered component shows the saved value; the DB has it too.
    expect(page).to have_css("[data-testid='current']", text: "after edit")
    expect(todo.reload.title).to eq("after edit")
  end
end
