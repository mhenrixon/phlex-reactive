# frozen_string_literal: true

require "system_helper"

# Issue #28: per-field reactive editing must NOT lose focus or drop the
# in-progress value when the debounced save fires. Response.morph(self) emits
# action="replace" method="morph", so Turbo 8's Idiomorph morphs the row in
# place — the focused <input> and its caret survive. With the old plain
# Response.replace this was a full outerHTML swap: the field was blurred and the
# just-typed value vanished (the failing Playwright assertion in the issue).
RSpec.describe "Morph grid — focus survives a save (issue #28)", type: :system do
  it "keeps focus on the field and persists the typed value through a morph save" do
    account = Account.create!(name: "old name")
    visit "/morph_grid/#{account.id}"
    page.execute_script("window.__noReload = 'alive'")

    field = find("[data-testid='name']")
    field.click # focus the field as a user would

    # Type a new value; the debounced `update` fires while the field is focused,
    # the action morphs the row in place.
    field.set("renamed live")

    # The morphed render reads the saved value back from the DB — proving the
    # round trip landed AND the value persisted (not dropped on a hard swap).
    expect(page).to have_css("[data-testid='saved']", text: "renamed live")
    expect(account.reload.name).to eq("renamed live")

    # The decisive morph assertion: after the save the field is STILL the active
    # element. A plain replace (outerHTML swap) would have destroyed it and blurred
    # focus to <body>; the morph preserves the live node.
    active_testid = page.evaluate_script("document.activeElement && document.activeElement.dataset.testid")
    expect(active_testid).to eq("name")

    # ...and the input still carries the typed value (caret/value preserved).
    expect(page).to have_field("name", with: "renamed live")

    # No full-page reload happened.
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
