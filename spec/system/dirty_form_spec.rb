# frozen_string_literal: true

require "system_helper"

# Dirty-field tracking (issue #103): reactive_root(track_dirty: true) re-scans the
# root's owned fields on every input, marking the root data-reactive-dirty="<count>"
# when a field diverges from its server-rendered defaultValue — with ZERO shipped
# state (the baseline is the DOM's own default attribute). An "Unsaved" badge is
# revealed purely by CSS ([data-reactive-dirty] .unsaved-badge). save morphs the
# field with the new value as its fresh default, so the post-morph re-scan clears
# the badge WITHOUT a full-page reload.
#
# Runs under Puma (sync) AND Falcon (async) in CI's server matrix.
RSpec.describe "Dirty-field tracking (issue #103)", type: :system do
  it "shows the unsaved badge on edit and clears it after a morph save — no reload" do
    todo = Todo.create!(title: "original")
    visit "/dirty_form/#{todo.id}"
    # Prove no full-page reload happens across the whole interaction.
    page.execute_script("window.__noReload = 'alive'")

    # At rest: clean form, no count on the root, badge hidden (CSS on the count).
    expect(page).to have_field("title", with: "original")
    expect(page).to have_no_css("[data-testid='badge']", visible: :visible)
    expect(page).to have_no_css("[id^='dirtyform'][data-reactive-dirty]")

    # Type a change → the field diverges from its defaultValue → the root gains a
    # count of 1, the field is marked dirty, and the badge becomes visible (CSS).
    find("[data-testid='title']").set("edited")
    expect(page).to have_css("[id^='dirtyform'][data-reactive-dirty='1']")
    expect(page).to have_css("[data-testid='title'][data-reactive-dirty='true']")
    expect(page).to have_css("[data-testid='badge']", visible: :visible, text: "Unsaved")

    # Save. reply.morph re-renders the field in place with "edited" as the NEW
    # defaultValue, so the post-morph re-scan finds it clean: the count/dirty
    # attrs drop and the badge hides again — all without navigating.
    find("[data-testid='save']").click

    expect(page).to have_css("[data-testid='current']", text: "edited") # morph landed
    expect(page).to have_no_css("[id^='dirtyform'][data-reactive-dirty]")
    expect(page).to have_no_css("[data-testid='title'][data-reactive-dirty]")
    expect(page).to have_no_css("[data-testid='badge']", visible: :visible)

    expect(todo.reload.title).to eq("edited")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "clears the badge when the field is edited back to its original value (full re-scan)" do
    todo = Todo.create!(title: "keepme")
    visit "/dirty_form/#{todo.id}"

    field = find("[data-testid='title']")
    field.set("changed")
    expect(page).to have_css("[id^='dirtyform'][data-reactive-dirty='1']")

    # Type the original value back — now equal to the default → clean again, even
    # without saving (the scan is a full re-compute, not a sticky flag).
    field.set("keepme")
    expect(page).to have_no_css("[id^='dirtyform'][data-reactive-dirty]")
    expect(page).to have_no_css("[data-testid='badge']", visible: :visible)
  end
end
