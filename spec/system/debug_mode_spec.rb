# frozen_string_literal: true

require "system_helper"

# Client debug mode end-to-end (issue #108). The /debug page renders the counter
# with Phlex::Reactive.debug ON, so the root carries data-reactive-debug="true"
# and the generic controller console.groups every dispatch. This spec overrides
# the console-group family to capture the trace, clicks increment, and asserts:
#   - a group WAS emitted, carrying the action, status, encoding, streams+target
#     and a token-refresh marker;
#   - the signed token VALUE never appears in any console argument.
# Runs under Puma AND Falcon — the trace must be identical sync and async.
RSpec.describe "Client debug mode (issue #108)", type: :system do
  it "console.groups the dispatch with NAMES/status/streams and never the token value" do
    visit "/debug"
    expect(page).to have_css("[data-testid='inc']")

    # The Ruby flag flowed to the DOM: the root is marked for the client to log.
    expect(page).to have_css("#counter[data-reactive-debug='true']")

    # Capture every console-group-family call into one string on window, and prove
    # no full-page navigation happened (marker survives).
    page.execute_script(<<~JS)
      window.__noReload = "alive"
      window.__debugLog = ""
      const record = (...args) => {
        window.__debugLog += args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" ") + "\\n"
      }
      console.group = record
      console.groupCollapsed = record
      console.log = record
    JS

    find("[data-testid='inc']").click
    expect(page).to have_css("[data-testid='count']", text: "1")

    log = page.evaluate_script("window.__debugLog")

    # The trace carries the action, the OK status, the JSON encoding, and the
    # self-replace stream targeting the counter id.
    expect(log).to include("increment")
    expect(log).to include("200")
    expect(log).to include("json")
    expect(log).to include("replace")
    expect(log).to include("counter")
    # A full self re-render refreshes the token — reported as a boolean marker.
    expect(log.downcase).to include("refresh")

    # The signed identity token VALUE is NEVER logged. Read the live token from the
    # DOM and assert it appears nowhere in the captured console output.
    token = page.evaluate_script("document.getElementById('counter').getAttribute('data-reactive-token-value')")
    expect(token).to be_a(String).and be_present
    expect(log).not_to include(token)

    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end
end
