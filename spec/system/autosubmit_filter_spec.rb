# frozen_string_literal: true

require "system_helper"

# Issue #226: the GENERAL autosubmit story — on_client(:change, js.submit("form"))
# on a select submits its own form with zero bespoke JS and zero reactive round
# trips. The form is a plain GET form: requestSubmit fires a real submit event,
# Turbo Drive turns it into a visit, and the page updates WITHOUT a full reload
# (the window marker survives — the testing-rules no-reload proof).
RSpec.describe "Autosubmit filter (issue #226)", type: :system do
  it "submits the form on change and re-renders without a full page reload" do
    visit "/autosubmit_filter"

    expect(page).to have_css("[data-testid='sorted-by']", text: "Sorted by: name")
    page.execute_script("window.__marker = 'kept'")

    find("[data-testid='sort']").find("option", text: "Price").select_option

    # Waiting matcher = the async barrier for the Turbo visit.
    expect(page).to have_css("[data-testid='sorted-by']", text: "Sorted by: price")
    expect(page.evaluate_script("window.__marker")).to eq("kept")
  end
end
