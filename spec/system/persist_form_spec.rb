# frozen_string_literal: true

require "system_helper"

# Issue #239: reactive_persist — a client-only localStorage draft over the
# fields a root owns. Typing is remembered across a reload and restored on the
# next connect (a reactive_show section re-evaluates from the restored value
# on first paint); a server-rendered non-blank value wins over the draft; the
# honeypot / hidden / password controls never reach storage; js.persist_state
# writes a state bag; js.persist_clear and a successful Turbo submit forget
# the draft. The fetch spy proves the reactive endpoint is never called and
# the marker proves the client ops never reload the page.
RSpec.describe "Client-only drafts (issue #239 — reactive_persist)", type: :system do
  def storage_key = "phlex-reactive:persist:dummy-apply"

  def install_fetch_spy
    page.execute_script(<<~JS)
      window.__fetchCount = 0
      const original = window.fetch
      window.fetch = (...args) => { window.__fetchCount += 1; return original(...args) }
    JS
  end

  def draft
    # The Playwright driver hands a JSON string back already decoded (and a
    # null as {}), so read through a sentinel and accept either shape.
    raw = page.evaluate_script(
      "(() => { const r = window.localStorage.getItem(#{storage_key.to_json}); return r === null ? '__none__' : r })()"
    )
    return nil if raw == "__none__"

    raw.is_a?(String) ? JSON.parse(raw) : raw
  end

  # Writes are debounced/async — poll the draft like a waiting matcher.
  def wait_for_draft
    deadline = Time.now + Capybara.default_max_wait_time
    loop do
      current = draft
      return current if current && yield(current)
      raise "draft never matched: #{current.inspect}" if Time.now > deadline

      sleep 0.05
    end
  end

  def clear_storage = page.execute_script("window.localStorage.clear()")

  it "remembers typed values across a reload, restores into blanks, and forgets on submit — zero fetches" do
    visit "/persist_form"
    clear_storage
    visit "/persist_form"
    page.execute_script("window.__noReload = 'alive'")
    install_fetch_spy

    fill_in "apply[name]", with: "Ada"
    fill_in "apply[bio]", with: "Builder"
    find("[data-testid='size-l']").click
    find("[data-testid='gift']").check
    fill_in "fuckery", with: "bot"
    fill_in "apply[secret]", with: "hunter2"
    expect(page).to have_css("[data-testid='large-note']", text: "Large surcharge")

    saved = wait_for_draft { it["fields"]["apply[name]"] == "Ada" && it["fields"]["apply[bio]"] == "Builder" }
    expect(saved["fields"]).to include("apply[size]" => "l", "apply[gift]" => true)
    expect(saved["fields"].keys).not_to include("fuckery", "apply[tz]", "apply[secret]")

    # js.persist_state — a client op: the bag lands in the draft AND on the root.
    find("[data-testid='next']").click
    expect(page).to have_css("#persist-form[data-reactive-persist-state='{\"step\":2}']")
    expect(wait_for_draft { it["state"] == { "step" => 2 } }["fields"]["apply[name]"]).to eq("Ada")

    expect(page.evaluate_script("window.__noReload")).to eq("alive")
    expect(page.evaluate_script("window.__fetchCount")).to eq(0)

    # Reload: the draft is restored on connect, the show section reads the
    # restored radio on FIRST PAINT (no click), the excluded controls stay blank.
    visit "/persist_form"
    expect(page).to have_field("apply[name]", with: "Ada")
    expect(page).to have_field("apply[bio]", with: "Builder")
    expect(find("[data-testid='size-l']")).to be_checked
    expect(find("[data-testid='gift']")).to be_checked
    expect(page).to have_css("[data-testid='large-note']", text: "Large surcharge")
    expect(page).to have_field("fuckery", with: "")
    expect(page).to have_field("apply[secret]", with: "")
    expect(find("[data-testid='tz']", visible: :hidden).value).to eq("UTC")
    expect(page).to have_css("#persist-form[data-reactive-persist-state='{\"step\":2}']")

    # A server-rendered non-blank value WINS over the draft (restore: :blank);
    # the other blanks still restore.
    visit "/persist_form?name=Server"
    expect(page).to have_field("apply[name]", with: "Server")
    expect(page).to have_field("apply[bio]", with: "Builder")

    # A successful Turbo form submit forgets the draft.
    visit "/persist_form"
    expect(page).to have_field("apply[name]", with: "Ada")
    find("[data-testid='submit']").click
    expect(page).to have_current_path(/submitted=1/)
    expect(page).to have_field("apply[name]", with: "")
    expect(draft).to be_nil
  end

  it "js.persist_clear forgets the draft without a reload" do
    visit "/persist_form"
    clear_storage
    visit "/persist_form"
    page.execute_script("window.__noReload = 'alive'")

    fill_in "apply[name]", with: "Ada"
    wait_for_draft { it["fields"]["apply[name]"] == "Ada" }
    find("[data-testid='discard']").click
    expect(page).to have_field("apply[name]", with: "Ada") # the DOM is untouched — only storage
    deadline = Time.now + Capybara.default_max_wait_time
    sleep 0.05 while draft && Time.now < deadline
    expect(draft).to be_nil
    expect(page.evaluate_script("window.__noReload")).to eq("alive")

    visit "/persist_form"
    expect(page).to have_field("apply[name]", with: "")
  end
end
