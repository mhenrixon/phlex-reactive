# frozen_string_literal: true

require "system_helper"

# Client lifecycle CustomEvents (issue #79). A page-level listener hears
# reactive:error when an action round trip fails — here forced via a trigger
# for an UNDECLARED action (the endpoint's default-deny → HTTP 403), the least
# invasive real failure. The events bubble, so `data-action=
# "reactive:error->toast#show"` on an ancestor composes the same way.
RSpec.describe "Lifecycle events (reactive:error)", type: :system do
  it "dispatches reactive:error with kind/status/retry when the endpoint refuses the action" do
    visit "/counter"
    expect(page).to have_css("[data-testid='boom']")

    # Marker proves the failure never triggered a full-page navigation, plus a
    # page-level probe node the document-level listener writes into.
    page.execute_script(<<~JS)
      window.__noReload = "alive"
      const probe = document.createElement("div")
      probe.setAttribute("data-testid", "error-probe")
      document.body.appendChild(probe)
      document.addEventListener("reactive:error", (event) => {
        const { kind, status, retry } = event.detail
        probe.textContent = [kind, status, typeof retry].join(":")
      })
    JS

    find("[data-testid='boom']").click

    # Undeclared action → default-deny 403 → kind=http, status=403, retry is a
    # callable. The waiting matcher is the barrier for the async round trip.
    expect(page).to have_css("[data-testid='error-probe']", text: "http:403:function")
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
