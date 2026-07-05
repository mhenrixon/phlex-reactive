# frozen_string_literal: true

require "system_helper"

# The on-demand client inspector (issue #168) in a REAL browser: load
# phlex/reactive/inspect on demand, scan() the live page, and prove the inventory
# maps the rendered reactive root back to its server Component#action names — the
# same identifiers `phlex_reactive:actions` / the MCP tools list. Runs under BOTH
# real servers (Puma default, Falcon via CAPYBARA_SERVER=falcon) since it is a
# client-touching change.
RSpec.describe "client inspector (phlex/reactive/inspect)", type: :system do
  it "scans the live page and names the component + its actions" do
    visit "/counter"
    expect(page).to have_css("[data-testid='count']", text: "0")

    # Dynamically import the vendored (minified) inspect module, scan the page,
    # and stash the JSON inventory on window for the Ruby side to read. The import
    # is async, so we store a readiness flag and poll it (there's no DOM change to
    # anchor a Capybara matcher on).
    page.execute_script(<<~JS)
      window.__inspectReady = (async () => {
        const { scan } = await import("/vendor/inspect.js")
        window.__inventory = scan()
        window.__inspectDone = true
      })()
    JS
    wait_for("inspect never scanned") { page.evaluate_script("window.__inspectDone === true") }

    inventory = page.evaluate_script("window.__inventory")
    counter = inventory.find { it["id"] == "counter" }

    expect(counter).not_to be_nil
    # The decoded token names the server component…
    expect(counter["component"]).to eq("CounterComponent")
    # …and the scanned triggers name its declared actions (increment/decrement are
    # both on the page), exactly the Component#action identifiers the server tools
    # list — the by-name server↔client mapping the docs page shows.
    actions = counter["triggers"].map { it["action"] }
    expect(actions).to include("increment", "decrement")
  end

  # Bounded poll on a JS window flag Capybara can't express as a waiting matcher.
  def wait_for(message = "condition never met", timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise message if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep(0.05)
    end
  end
end
