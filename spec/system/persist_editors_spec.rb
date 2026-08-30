# frozen_string_literal: true

require "system_helper"

# Issue #241: reactive_persist over RICH editors — the real Trix (2.1.19) and
# Lexxy (0.9.31) plus a bare named contenteditable, vendored into the dummy.
# Typing into each editor lands in the draft under its resolved name (Trix's
# name comes from its `input=`-paired hidden input, which is itself never a
# separate key); a reload restores each through the editor's OWN value
# surface; a server-rendered body wins over the draft (restore: :blank asks
# the editor whether it is empty); the skip marker on an editor element is
# honoured; and the editors defined AFTER the reactive controller connected
# (?late=1 — and Trix always, since it defines its elements in a setTimeout)
# are restored once customElements.whenDefined resolves. The fetch spy proves
# the reactive endpoint is never called; the marker proves no reload.
RSpec.describe "Client-only drafts over rich editors (issue #241 — reactive_persist)", type: :system do
  def storage_key = "phlex-reactive:persist:dummy-editors"

  def install_fetch_spy
    page.execute_script(<<~JS)
      window.__fetchCount = 0
      const original = window.fetch
      window.fetch = (...args) => { window.__fetchCount += 1; return original(...args) }
    JS
  end

  def draft
    raw = page.evaluate_script(
      "(() => { const r = window.localStorage.getItem(#{storage_key.to_json}); return r === null ? '__none__' : r })()"
    )
    return nil if raw == "__none__"

    raw.is_a?(String) ? JSON.parse(raw) : raw
  end

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

  # The editors' own serialized values (the exact strings the draft holds).
  def editor_value(testid)
    page.evaluate_script("document.querySelector(\"[data-testid='#{testid}']\").value")
  end

  # Lexxy's typing surface is its inner content element (the host element is
  # not editable); Trix and the bare div are contenteditable themselves.
  def type_into(testid, text)
    target = "[data-testid='#{testid}']"
    target += " .lexxy-editor__content" if %w[body private].include?(testid)
    find(target).click
    page.send_keys(text)
  end

  def fresh_visit(path = "/persist_editors")
    visit path
    clear_storage
    visit path
    expect(page).to have_css("lexxy-editor[connected]") # both editors upgraded + connected
    expect(page).to have_css("trix-editor[connected]")
  end

  it "drafts each editor under its resolved name and restores through the editors' own value surfaces" do
    fresh_visit
    page.execute_script("window.__noReload = 'alive'")
    install_fetch_spy

    fill_in "draft[title]", with: "Title"
    type_into("body", "Essay body")
    type_into("notes", "Trix notes")
    type_into("summary", "Plain summary")
    type_into("private", "never stored")

    saved = wait_for_draft do
      it["fields"]["draft[body]"].to_s.include?("Essay body") &&
      it["fields"]["draft[notes]"].to_s.include?("Trix notes") &&
      it["fields"]["draft[summary]"] == "Plain summary"
    end
    expect(saved["fields"]["draft[title]"]).to eq("Title")
    expect(saved["fields"]["draft[body]"]).to start_with("<") # Lexxy's serialized HTML
    expect(saved["fields"]["draft[notes]"]).to start_with("<") # Trix's serialized HTML
    expect(saved["fields"].keys).not_to include("draft[private]")
    expect(saved["fields"].keys.count("draft[notes]")).to eq(1)

    expect(page.evaluate_script("window.__noReload")).to eq("alive")
    expect(page.evaluate_script("window.__fetchCount")).to eq(0)

    # Reload: each editor shows its restored text (through its own setter — the
    # rendered text is the proof it went through the editor, not innerHTML).
    visit "/persist_editors"
    expect(page).to have_field("draft[title]", with: "Title")
    expect(page).to have_css("[data-testid='body']", text: "Essay body")
    expect(page).to have_css("[data-testid='notes']", text: "Trix notes")
    expect(page).to have_css("[data-testid='summary']", text: "Plain summary")
    expect(page).to have_no_css("[data-testid='private']", text: "never stored")
    expect(editor_value("body")).to eq(saved["fields"]["draft[body]"])
    expect(editor_value("notes")).to eq(saved["fields"]["draft[notes]"])
    expect(find("[data-testid='notes-input']", visible: :hidden).value).to eq(saved["fields"]["draft[notes]"])

    # A server-rendered body WINS (restore: :blank asks the editor — a Lexxy
    # value of "<p><br></p>" is empty, a real paragraph is not); the others
    # still restore.
    query = Rack::Utils.build_query(body: "<p>Server body</p>", notes: "<div>Server notes</div>")
    visit "/persist_editors?#{query}"
    expect(page).to have_css("[data-testid='body']", text: "Server body")
    expect(page).to have_css("[data-testid='notes']", text: "Server notes")
    expect(page).to have_css("[data-testid='summary']", text: "Plain summary")
    expect(page).to have_no_css("[data-testid='body']", text: "Essay body")
    expect(page).to have_no_css("[data-testid='notes']", text: "Trix notes")

    # Editors defined AFTER connect are restored once they upgrade.
    visit "/persist_editors?late=1"
    expect(page).to have_css("[data-testid='body']", text: "Essay body")
    expect(page).to have_css("[data-testid='notes']", text: "Trix notes")
    expect(page).to have_css("[data-testid='summary']", text: "Plain summary")

    # A successful Turbo form submit forgets the draft.
    visit "/persist_editors"
    expect(page).to have_css("[data-testid='body']", text: "Essay body")
    find("[data-testid='submit']").click
    expect(page).to have_current_path(/submitted=1/)
    expect(page).to have_css("lexxy-editor[connected]")
    expect(page).to have_no_css("[data-testid='body']", text: "Essay body")
    expect(draft).to be_nil
  end

  it "js.persist_clear forgets an editor draft without a reload" do
    fresh_visit
    page.execute_script("window.__noReload = 'alive'")

    type_into("body", "Essay body")
    wait_for_draft { it["fields"]["draft[body]"].to_s.include?("Essay body") }
    find("[data-testid='discard']").click
    deadline = Time.now + Capybara.default_max_wait_time
    sleep 0.05 while draft && Time.now < deadline
    expect(draft).to be_nil
    expect(page.evaluate_script("window.__noReload")).to eq("alive")

    visit "/persist_editors"
    expect(page).to have_css("lexxy-editor[connected]")
    expect(page).to have_no_css("[data-testid='body']", text: "Essay body")
  end
end
