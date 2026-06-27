# frozen_string_literal: true

require "system_helper"

# Issue #15: a reactive component rendered INSIDE another reactive component is
# its own root. An action on the OUTER editor must collect only the editor's own
# named inputs — NOT the nested rows' inputs. Pre-fix, the editor's save swept
# every descendant input (including each row's bare `quantity`), so the editor
# received row fields it never declared.
RSpec.describe "Nested reactive roots (issue #15)", type: :system do
  it "the outer editor's save collects only its own fields, not nested rows'" do
    visit "/nested_editor"

    # Marker proves no full-page navigation happened.
    page.execute_script("window.__noReload = 'alive'")

    find("[data-testid='editor-notes']").set("editor only")
    find("[data-testid='editor-save']").click

    # The save ran (no 403 from an undeclared `quantity`, no collision) and
    # recorded ONLY the editor's own notes — the nested rows never bled in.
    expect(page).to have_css("[data-testid='editor-saved']", text: "saved:editor only")

    # The nested rows are untouched by the editor's save.
    expect(page).to have_css("[data-testid='row-echo-a']", text: "11")
    expect(page).to have_css("[data-testid='row-echo-b']", text: "22")

    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "an action on a nested row still collects that row's own fields" do
    visit "/nested_editor"
    page.execute_script("window.__noReload = 'alive'")

    field = find("[data-testid='row-qty-a']")
    field.set("99")
    # Set the value AND fire change explicitly so the row's own update dispatches
    # (Capybara's blur alone proved flaky under Playwright here).
    field.native.evaluate("el => { el.value = '99'; el.dispatchEvent(new Event('change', { bubbles: true })) }")

    # Row A updated to its own field's value; Row B is unaffected; the editor is
    # unaffected.
    expect(page).to have_css("[data-testid='row-echo-a']", text: "99")
    expect(page).to have_css("[data-testid='row-echo-b']", text: "22")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
