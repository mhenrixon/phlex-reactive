# frozen_string_literal: true

require "system_helper"

# Issue #180 Phase A: reactive_show — value-conditional visibility via the ONE
# conditions language (if:/if_any:/unless:). Dependent sections show/hide from
# fields' CURRENT values entirely client-side: a fetch spy wrapped around
# window.fetch BEFORE any interaction proves the reactive endpoint is never
# called, and the no-reload marker proves the page never navigates. First paint
# is server-computed from reactive_values (no flash), including the OR-of-AND
# case a production adopter had to decompose by hand.
RSpec.describe "Value-conditional visibility (issue #180 — conditions language)", type: :system do
  def install_fetch_spy
    page.execute_script(<<~JS)
      window.__fetchCount = 0
      const original = window.fetch
      window.fetch = (...args) => { window.__fetchCount += 1; return original(...args) }
    JS
  end

  it "shows/hides via if:/if_any:/unless:/Range — zero fetches, no reload" do
    visit "/conditional_fieldset"
    page.execute_script("window.__noReload = 'alive'")
    install_fetch_spy

    # First paint (server-computed from reactive_values — no flash): every
    # dependent section renders hidden, and the cross-root badge too.
    expect(page).to have_css("[data-testid='mode-details']", visible: :hidden)
    expect(page).to have_css("[data-testid='gift-note']", visible: :hidden)
    expect(page).to have_css("[data-testid='address']", visible: :hidden)
    expect(page).to have_css("[data-testid='intl-address']", visible: :hidden)
    expect(page).to have_css("[data-testid='name-fields']", visible: :hidden)
    expect(page).to have_css("[data-testid='surcharge']", visible: :hidden)
    expect(page).to have_css("[data-testid='mode-badge']", visible: :hidden)

    # unless: — visible WHILE mode != "off"; the cross-root badge (a membership
    # Array = standard OR express) toggles from the same change.
    select "Express", from: "mode"
    expect(page).to have_css("[data-testid='mode-details']", text: "Shipping details")
    expect(page).to have_css("[data-testid='mode-badge']", text: "Shipping enabled")
    select "No shipping", from: "mode"
    expect(page).to have_css("[data-testid='mode-details']", visible: :hidden)
    expect(page).to have_css("[data-testid='mode-badge']", visible: :hidden)

    # if: { gift: true } — checkbox checked-state.
    find("[data-testid='gift']").check
    expect(page).to have_css("[data-testid='gift-note']", text: "Gift message")
    find("[data-testid='gift']").uncheck
    expect(page).to have_css("[data-testid='gift-note']", visible: :hidden)

    # if: { delivery: "ship" } — radio checked value.
    find("[data-testid='delivery-ship']").click
    expect(page).to have_css("[data-testid='address']", text: "Shipping address")
    find("[data-testid='delivery-pickup']").click
    expect(page).to have_css("[data-testid='address']", visible: :hidden)

    # Compound AND (if: + unless:): individual AND not domestic.
    select "Foreign", from: "country"
    expect(page).to have_css("[data-testid='intl-address']", text: "International address")
    select "Company", from: "type"
    expect(page).to have_css("[data-testid='intl-address']", visible: :hidden)
    select "Individual", from: "type"
    expect(page).to have_css("[data-testid='intl-address']", text: "International address")

    # Numeric Range + disable: reveal while quantity >= 10; the hidden control is
    # disabled so it can't submit a stale value (the field exists but is hidden,
    # so match visible: :all).
    expect(page).to have_css("[data-testid='surcharge']", visible: :hidden)
    expect(page).to have_field("bulk_ack", disabled: true, visible: :all)
    fill_in "quantity", with: "12"
    expect(page).to have_css("[data-testid='surcharge']", text: "Bulk surcharge applies")
    expect(page).to have_field("bulk_ack", disabled: false)
    fill_in "quantity", with: "5"
    expect(page).to have_css("[data-testid='surcharge']", visible: :hidden)
    expect(page).to have_field("bulk_ack", disabled: true, visible: :all)

    # The whole exchange was client-side: not one fetch, no full-page reload.
    expect(page.evaluate_script("window.__fetchCount")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  # The distributive-law killer (issue #180): director OR (shareholder AND
  # role == "individual") in ONE if_any: binding — the exact shape a production
  # adopter had to decompose into nested wrapper divs. A company shareholder
  # must NOT reveal the name fields (the superset bug the adopter's system spec
  # caught); a director alone MUST.
  it "handles OR-of-AND (name fields) without a superset false-positive" do
    visit "/conditional_fieldset"
    install_fetch_spy

    expect(page).to have_css("[data-testid='name-fields']", visible: :hidden)

    # Director alone → visible (first group).
    find("[data-testid='director']").check
    expect(page).to have_css("[data-testid='name-fields']", text: "Name fields")

    # Uncheck director, check shareholder with role=company → the SUPERSET bug:
    # a naive any:[director, shareholder] would wrongly reveal here.
    find("[data-testid='director']").uncheck
    find("[data-testid='shareholder']").check
    select "Company", from: "role"
    expect(page).to have_css("[data-testid='name-fields']", visible: :hidden)

    # Shareholder + role=individual → visible (second group).
    select "Individual", from: "role"
    expect(page).to have_css("[data-testid='name-fields']", text: "Name fields")

    expect(page.evaluate_script("window.__fetchCount")).to eq(0)
  end

  # Issue #209: the cross-root MULTI-FIELD target — an outside alert reading
  # TWO owned fields (type == "company" AND quantity >= 10) via a target-keyed
  # conditions Hash, declared in the SAME reactive_show_targets call as the
  # single-field badge (the mixed one-call form — mix would space-join a second
  # call). The exact case that used to force a bespoke two-field JS listener.
  it "toggles a cross-root target from a COMBINATION of fields — zero fetches" do
    visit "/conditional_fieldset"
    install_fetch_spy

    expect(page).to have_css("[data-testid='bulk-alert']", visible: :hidden)

    # One field matching is not enough — the AND holds it closed.
    select "Company", from: "type"
    expect(page).to have_css("[data-testid='bulk-alert']", visible: :hidden)

    # Both match → the outside alert reveals.
    fill_in "quantity", with: "12"
    expect(page).to have_css("[data-testid='bulk-alert']", text: "approval needed")

    # EITHER field leaving its range re-hides it.
    select "Individual", from: "type"
    expect(page).to have_css("[data-testid='bulk-alert']", visible: :hidden)
    select "Company", from: "type"
    expect(page).to have_css("[data-testid='bulk-alert']", text: "approval needed")
    fill_in "quantity", with: "5"
    expect(page).to have_css("[data-testid='bulk-alert']", visible: :hidden)

    # The single-field badge in the SAME call still works (the mixed map).
    select "Express", from: "mode"
    expect(page).to have_css("[data-testid='mode-badge']", text: "Shipping enabled")

    expect(page.evaluate_script("window.__fetchCount")).to eq(0)
  end
end
