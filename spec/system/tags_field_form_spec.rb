# frozen_string_literal: true

require "system_helper"

# The end-to-end proof of the issue #224 escape hatches, in the exact shape a
# form-builder gem (phlex-forms' tag_field) renders:
#
#   * reactive_tags(name: "user[tags]") — the client resolves the VERBATIM
#     bracketed wire name to the hidden field (adds/removes maintain it).
#   * reactive_filter(input: "#user_tags_query") — the client resolves the
#     query input BY ID, so the input needs NO name … and the real form submit
#     proves it: user[tags] arrives comma-joined with ZERO stray params.
#
# The blessed-form behaviors (spec/system/tags_field_spec.rb) are already
# covered — this spec exercises the same client paths through the escape-hatch
# wire only.
RSpec.describe "Tag-chip input, form-builder shape (issue #224)", type: :system do
  def install_fetch_spy
    page.execute_script(<<~JS)
      window.__actionPosts = 0
      const orig = window.fetch
      window.fetch = (url, opts) => {
        if (String(url).includes("/reactive/actions")) window.__actionPosts++
        return orig(url, opts)
      }
      window.__noReload = "alive"
    JS
  end

  def hidden_value
    find("[data-testid='form-tags-value']", visible: :hidden).value
  end

  it "filters, adds, and removes entirely client-side through the verbatim wire" do
    visit "/form_tags_field"
    expect(page).to have_css("[data-testid='form-tags-query']")
    install_fetch_spy

    # The filter resolves the id-targeted, NAME-LESS input: typing narrows by
    # haystack ("db" never appears in the Postgres label).
    query = find("[data-testid='form-tags-query']")
    expect(query[:name]).to be_nil.or eq("")
    query.send_keys("db")
    expect(page).to have_css("[role=option]", count: 1)

    # Click-to-add writes the bracketed hidden field (the verbatim name: wire).
    find("[data-testid='form-option-postgres']").click
    expect(page).to have_css("[data-testid='form-tag-chip']", text: "Postgres")
    expect(hidden_value).to eq("Postgres")

    # Enter free text appends; remove drops back to one.
    query.send_keys("Elixir", :enter)
    expect(page).to have_css("[data-testid='form-tag-chip']", count: 2)
    expect(hidden_value).to eq("Postgres,Elixir")

    within("[data-reactive-tag='Elixir']") { click_button "×" }
    expect(page).to have_css("[data-testid='form-tag-chip']", count: 1)
    expect(hidden_value).to eq("Postgres")

    # All of it client-side: no action POST, no navigation.
    expect(page.evaluate_script("window.__actionPosts")).to eq(0)
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "a real submit carries user[tags] comma-joined and NO stray query param" do
    visit "/form_tags_field"
    expect(page).to have_css("[data-testid='form-tags-query']")

    query = find("[data-testid='form-tags-query']")
    query.send_keys("Ruby", :enter)
    expect(page).to have_css("[data-testid='form-tag-chip']", text: "Ruby")
    find("[data-testid='form-option-hotwire']").click
    expect(page).to have_css("[data-testid='form-tag-chip']", text: "Hotwire")

    find("[data-testid='form-tags-submit']").click

    # The server received user[tags] and re-rendered the chips server-side.
    expect(page).to have_css("[data-testid='form-tags-submitted']", text: "Saved: Ruby,Hotwire")
    expect(page).to have_css("[data-testid='form-tag-chip']", count: 2)
    expect(hidden_value).to eq("Ruby,Hotwire")

    # The name-less query input contributed NOTHING to the submit.
    expect(find("[data-testid='form-tags-stray']").text).to eq("")
  end
end
