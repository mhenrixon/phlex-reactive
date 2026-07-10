# frozen_string_literal: true

require "system_helper"

# End-to-end proof of per-row confirm INTERPOLATION on client-added rows
# (issue #222). The remove trigger's confirm carries a %{quantity} placeholder
# on the <template>; a row added via reactive_nested_add is a cloneNode of that
# template, so before #222 it showed the frozen literal "%{quantity}". Now the
# client interpolates %{field} from the added row's OWN live field values at
# click time, so the confirm reflects the quantity the user typed into THAT row.
#
# window.confirm is overridden in the page to RECORD the message it was shown
# (and decline), so the assertion is on the string the gate produced — the whole
# point — deterministic across both drivers and both servers (Puma + Falcon).
RSpec.describe "Draft order form — per-row confirm interpolation (issue #222)", type: :system do
  # Override window.confirm to record every message and return the given answer.
  def record_confirm(answer:)
    page.execute_script(<<~JS)
      window.__confirmMessages = []
      window.confirm = (message) => {
        window.__confirmMessages.push(message)
        return #{answer ? "true" : "false"}
      }
    JS
  end

  def confirm_messages
    page.evaluate_script("window.__confirmMessages || []")
  end

  it "interpolates the ADDED row's own typed quantity into its confirm message" do
    visit "/draft_order_confirm_interpolate"
    expect(page).to have_css("[data-testid='add-item']")

    # Add two rows and type a DIFFERENT quantity into each — the whole test is
    # that each row's confirm reflects ITS OWN value, not the template's blank.
    find("[data-testid='add-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 1)
    find("[data-testid='add-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 2)

    rows = page.all("[data-testid='item-row']")
    rows[0].find("[data-testid='qty']").set(7)
    rows[1].find("[data-testid='qty']").set(3)

    # Decline the FIRST row's remove → the message must carry that row's 7,
    # NOT the template's "%{quantity}" and NOT the other row's 3.
    record_confirm(answer: false)
    rows[0].find("[data-testid='remove-item']").click

    expect(page).to have_css("[data-testid='item-row']", count: 2) # declined → both stay
    expect(confirm_messages).to eq(["Remove line item with quantity 7?"])
  end

  it "reflects a LATER edit (interpolation is live at click time, not clone time)" do
    visit "/draft_order_confirm_interpolate"
    expect(page).to have_css("[data-testid='add-item']")

    find("[data-testid='add-item']").click
    expect(page).to have_css("[data-testid='item-row']", count: 1)

    row = page.first("[data-testid='item-row']")
    row.find("[data-testid='qty']").set(4)

    # Accept → the row leaves; the message shown carries the EDITED value.
    record_confirm(answer: true)
    row.find("[data-testid='remove-item']").click

    expect(page).to have_css("[data-testid='item-row']", count: 0)
    expect(confirm_messages).to eq(["Remove line item with quantity 4?"])
  end
end
