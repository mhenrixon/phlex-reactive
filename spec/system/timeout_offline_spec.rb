# frozen_string_literal: true

require "system_helper"

# Request timeout + offline handling end-to-end (issue #101). A hung request no
# longer wedges the per-component queue, and going offline surfaces a retriable
# error + a CSS hook instead of silently half-sending. Runs under Puma AND Falcon
# (the reactive round trip must behave the same sync and async).
RSpec.describe "Timeout + offline (issue #101)", type: :system do
  # Reach the Playwright browser context to toggle offline (the driver exposes
  # the underlying page; its context has set_offline).
  def toggle_offline(offline)
    page.driver.with_playwright_page do
      it.context.set_offline(offline)
    end
  end

  describe "offline" do
    after { toggle_offline(false) } # never leak offline into the next example

    it "sets data-reactive-offline on <html> and fires reactive:error kind=offline, skipping the fetch" do
      visit "/network_status"
      expect(page).to have_css("[data-testid='ping']")

      page.execute_script('window.__noReload = "alive"')
      toggle_offline(true)

      # The online/offline events toggle the CSS hook on <html>.
      expect(page).to have_css("html[data-reactive-offline]")

      # A click while offline short-circuits: the fetch never fires, the edit is
      # not applied (count stays 0), and reactive:error kind=offline is dispatched.
      find("[data-testid='ping']").click
      expect(page).to have_css("[data-testid='error-probe']", text: "offline")
      expect(page).to have_css("[data-testid='count']", text: "0") # never sent
      expect(page.evaluate_script("window.__noReload")).to eq("alive")

      # Back online clears the flag.
      toggle_offline(false)
      expect(page).to have_no_css("html[data-reactive-offline]")
    end
  end

  describe "timeout" do
    it "aborts a hung request (kind=timeout) and does NOT wedge the queue" do
      visit "/network_status"
      expect(page).to have_css("[data-testid='slow']")

      # The slow action sleeps 2.5s; the page's phlex-reactive-timeout meta is
      # 1000ms, so the client aborts the fetch → reactive:error kind=timeout.
      find("[data-testid='slow']").click
      expect(page).to have_css("[data-testid='error-probe']", text: "timeout")

      # THE CRITICAL ASSERTION: the hung request did not wedge this.queue. A
      # subsequent ping still round-trips and re-renders (count → 1). Before the
      # timeout mechanism, the queue chained on a promise that never resolved, so
      # every future action was frozen and this would never update.
      #
      # The slow action still occupies a server thread until its 2.5s sleep ends;
      # let it drain so the ping isn't itself starved past its own client timeout
      # (this test proves the CLIENT queue recovered, not server concurrency).
      sleep 2.5

      find("[data-testid='ping']").click
      expect(page).to have_css("[data-testid='count']", text: "1", wait: 8)
    end
  end
end
