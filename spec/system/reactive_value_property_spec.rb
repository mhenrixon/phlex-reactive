# frozen_string_literal: true

require "system_helper"

# have_reactive_value must read the field's live `.value` PROPERTY, not the value
# ATTRIBUTE (issue #204). A reactive_compute reducer paints a computed output by
# setting `el.value = …` (the property); for a DISABLED / read-only output the
# value attribute never reflects that, so the attribute-based have_field(with:)
# reads "" and fails. The property read covers enabled AND disabled fields — the
# exact case the matcher was built for.
#
# Waiting matchers are the barrier for every async hop — never a snapshot right
# after a click.
RSpec.describe "have_reactive_value reads the .value property (issue #204)", type: :system do
  it "verifies a DISABLED reducer-set output (the attribute stays blank; the property holds the value)" do
    visit "/compute_seed"

    # total_ro is disabled and seeded blank; the connect-time compute sets its
    # `.value` PROPERTY to the total (2 + 4 = 6). have_reactive_value reads the
    # property, so it settles on "6" — where have_field(with:) would read the
    # empty attribute and fail.
    expect(page).to have_reactive_value("total_ro", "6")

    # Prove the field really is disabled AND its value ATTRIBUTE is still blank —
    # so this assertion could ONLY have passed by reading the property. The field
    # has a `name` (reactive_field emits name, not id), so resolve by name.
    expect(page).to have_field("total_ro", disabled: true)
    expect(page.evaluate_script("document.getElementsByName('total_ro')[0].getAttribute('value')")).to eq("")
    expect(page.evaluate_script("document.getElementsByName('total_ro')[0].value")).to eq("6")
  end

  it "still verifies an ENABLED reducer-set output (backwards compatible)" do
    visit "/compute_seed"

    expect(page).to have_reactive_value("total", "6")
    expect(page).to have_reactive_value("half", "3")
  end

  it "supports negation — a wrong expected value does not match" do
    visit "/compute_seed"
    # Wait for the layer to settle first, then the negated assertion is stable.
    wait_for_reactive
    expect(page).not_to have_reactive_value("total_ro", "999")
  end
end
