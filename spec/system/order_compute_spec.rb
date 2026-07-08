# frozen_string_literal: true

require "system_helper"

# The end-to-end proof of the reactive_compute / new-vs-persisted split (Option C):
#
#   * A NEW (unsaved) order recomputes the payment split IN-BROWSER via
#     reactive_compute — cash updates instantly with NO round trip to the server.
#   * A PERSISTED order routes the same edit through the reactive rebalance action;
#     the server runs the SAME PaymentSplit twin and streams cash back, persisting.
#
# One math contract (PaymentSplit ⇄ payment_split_reducer.js), two execution sites.
RSpec.describe "Order payment split (reactive_compute new vs persisted)", type: :system do
  describe "a NEW (unsaved) order" do
    it "recomputes cash in-browser with NO server round trip" do
      visit "/new_order"
      expect(page).to have_field("total", with: "500")
      # Issue #199: the compute root SELF-SEEDS on connect, so the split paints on
      # first render (total 500 − allowance 0 = cash 500) — no wait for the first
      # edit. (Before #199 this read "0", the unseeded field value.)
      expect(page).to have_field("cash", with: "500")

      # Count reactive action POSTs: a client-side compute must fire ZERO.
      page.execute_script(<<~JS)
        window.__actionPosts = 0
        const orig = window.fetch
        window.fetch = (url, opts) => {
          if (String(url).includes("/reactive/actions")) window.__actionPosts++
          return orig(url, opts)
        }
        window.__noReload = "alive"

        // A chained/derived repaint hanging off the computed output (issue #76):
        // real browsers do NOT fire `input` on a programmatic .value write, so
        // this listener only runs if the controller dispatches the event itself.
        const echo = document.createElement("output")
        echo.id = "cash-echo"
        document.body.appendChild(echo)
        document.querySelector('[name="cash"]').addEventListener("input", (e) => {
          echo.textContent = "cash is " + e.target.value
        })
      JS

      # Type an allowance; the reducer runs on `input` and writes cash = 500 - 100.
      fill_in "allowance", with: "100"

      expect(page).to have_field("cash", with: "400") # instant, client-computed
      # The chained listener repainted via the controller's dispatched input event.
      expect(page).to have_css("#cash-echo", text: "cash is 400")
      expect(page.evaluate_script("window.__actionPosts")).to eq(0) # NO round trip
      expect(page.evaluate_script("window.__noReload")).to eq("alive") # no reload

      # A second edit recomputes again, still client-side.
      fill_in "allowance", with: "200"
      expect(page).to have_field("cash", with: "300")
      expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    end
  end

  describe "a PERSISTED order" do
    let(:order) { Order.create!(total: 500, allowance: 0, cash: 500, leasing: 0) }

    it "rebalances through the server and persists the split" do
      visit "/order/#{order.id}"
      expect(page).to have_field("cash", with: "500")
      page.execute_script("window.__noReload = 'alive'")

      # Editing allowance fires the reactive rebalance action (change trigger);
      # the server recomputes cash and streams the component back.
      fill_in "allowance", with: "100"
      find("body").click # blur → the `change` event fires the reactive dispatch

      expect(page).to have_field("cash", with: "400") # server-reconciled
      expect(page.evaluate_script("window.__noReload")).to eq("alive") # no reload

      # The server persisted it (the DB is the source of truth for a saved order).
      expect(order.reload.allowance).to eq(100)
      expect(order.cash).to eq(400)
    end
  end
end
