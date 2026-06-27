# frozen_string_literal: true

require "system_helper"

# Issue #16: a reactive action whose schema declares nested/array params is
# invoked end-to-end through the real client. Explicit params passed to
# on(:save, ...) are JSON-serialized, posted, coerced server-side (recursing for
# the array-of-hash), and the component re-renders with the coerced structure.
RSpec.describe "Nested/array params end-to-end (issue #16)", type: :system do
  it "round-trips nested attributes through the reactive action" do
    visit "/nested_params"
    page.execute_script("window.__noReload = 'alive'")

    # Drive the action with explicit nested params (the `on(...)` extra-params
    # path), exercising the real wire format + recursive coercion in the browser.
    page.execute_script(<<~JS)
      const root = document.getElementById("nested-params")
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(root, "reactive")
      ctrl.dispatch({
        params: {
          action: "save",
          params: JSON.stringify({
            date: "2026-06-27",
            bank_account_ids: ["1", "2"],
            invoice_items_attributes: [{ id: "10", quantity: "2.5", price: "9.99", _destroy: "false" }]
          })
        },
        preventDefault() {}
      })
    JS

    # The re-rendered <pre> reflects the COERCED structure (integers/floats/bools).
    expect(page).to have_css("[data-testid='received']", text: '"bank_account_ids":[1,2]')
    expect(page).to have_css("[data-testid='received']", text: '"quantity":2.5')
    expect(page).to have_css("[data-testid='received']", text: '"_destroy":false')
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
