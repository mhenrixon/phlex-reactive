# frozen_string_literal: true

require "system_helper"

# Issue #159: cross-root text mirrors. The new-order page shows a read-only
# recap OUTSIDE the component's reactive root — root isolation (issue #15)
# makes it invisible to reactive_text, so the component DECLARES the escape:
#
#   reactive_compute :payment_split, …,
#     mirror: { cash: "#summary-cash", total: "#summary-total" }
#
# On every compute pass the declared id targets are painted via textContent —
# cash from the reducer result, total from its field's identity value — with
# NO bespoke listener and NO round trip.
RSpec.describe "Cross-root compute mirror (issue #159)", type: :system do
  it "paints declared recap nodes OUTSIDE the reactive root, with no round trip" do
    visit "/new_order"
    # Issue #199: the compute root SELF-SEEDS on connect, so the declared mirrors
    # paint on FIRST render — #summary-cash from the reducer result (500) and
    # #summary-total from the total field's identity value (500). The recap seeds
    # "—", so seeing "500" here PROVES the connect-time paint fired (the text had
    # to change). (Before #199 these read "0" / "—" until the first edit.)
    expect(page).to have_css("#summary-cash", text: "500")
    expect(page).to have_css("#summary-total", text: "500")

    # Count reactive action POSTs — the mirror is a pure client paint.
    page.execute_script(<<~JS)
      window.__actionPosts = 0
      const orig = window.fetch
      window.fetch = (url, opts) => {
        if (String(url).includes("/reactive/actions")) window.__actionPosts++
        return orig(url, opts)
      }
      window.__noReload = "alive"
    JS

    fill_in "allowance", with: "100"

    # The in-root split still recomputed…
    expect(page).to have_field("cash", with: "400")
    # …and the recap OUTSIDE the root repainted through the declared mirror — a
    # visible CHANGE from the seeded 500, so the on-edit paint is proven too.
    expect(page).to have_css("#summary-cash", text: "400")  # reducer-result value
    expect(page).to have_css("#summary-total", text: "500") # input identity value
    expect(page.evaluate_script("window.__actionPosts")).to eq(0) # NO round trip
    expect(page.evaluate_script("window.__noReload")).to eq("alive") # no reload

    # A second edit keeps the recap live.
    fill_in "allowance", with: "250"
    expect(page).to have_css("#summary-cash", text: "250")
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
  end
end
