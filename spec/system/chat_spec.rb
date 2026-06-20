# frozen_string_literal: true

require "system_helper"

RSpec.describe "Chat (reactive action + broadcast)", type: :system do
  # Sending: the reactive action persists the message and clears the composer.
  # The message reaches the list via a BROADCAST (covered deterministically by
  # spec/requests/chat_broadcast_spec.rb — same-tab WebSocket delivery is too
  # flaky to assert in a headless harness with the test cable adapter).
  it "sends a message via the reactive action and clears the composer" do
    visit "/chat"
    expect(page).to have_css("#chat-messages-lobby")

    page.execute_script("window.__noReload = 'alive'")

    find("[data-testid='chat-input']").set("hello reactive world")
    find("[data-testid='chat-send']").click

    # The action response re-renders the composer with a cleared input. This is
    # a waiting matcher, so it also serves as our barrier for the round trip.
    expect(page).to have_field("body", with: "")

    # By now the round trip completed, so the message exists server-side …
    expect(ChatMessage.where(body: "hello reactive world")).to exist
    # … and no full-page reload happened.
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "renders existing messages on load" do
    ChatMessage.create!(room: "lobby", author: "seed", body: "earlier message")
    visit "/chat"
    expect(page).to have_css("[data-testid='message']", text: "earlier message")
  end
end
