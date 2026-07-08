# frozen_string_literal: true

require 'system_helper'

# The live chat room embedded on the example page: sending a message creates it,
# appends it to the SENDER's own list via their reply, and broadcasts it to every
# OTHER subscribed tab (excluding the actor). So a single session sees its own
# message immediately — the same actor-via-reply / others-via-excluded-broadcast
# pattern as the todo list and inbox examples. (True cross-tab delivery still needs
# a real pub/sub backend — pgbus in production; the demo's in-process async cable
# fans out cross-CLIENT.)
RSpec.describe 'Chat example page', type: :system do
  before { ChatMessage.delete_all }

  it 'sends a message on click — the sender sees it, the composer clears (no reload)' do
    visit '/docs/example-chat'
    page.execute_script("window.__noReload = 'alive'")

    within first("[data-testid='live-example-demo']") do
      expect(page).to have_css("[data-testid='chat-messages']")
      find("[data-testid='chat-input']").set('hello from the docs page')
      find("[data-testid='chat-send']").click

      # The sender's own message appears in their list (reply append), and the
      # composer re-renders clear.
      expect(page).to have_css("[data-testid='message-body']", text: 'hello from the docs page')
      expect(page).to have_field('body', with: '')
    end

    expect(ChatMessage.where(body: 'hello from the docs page')).to exist
    expect(page.evaluate_script('window.__noReload')).to eq('alive')
  end

  it 'sends on Enter in the input (same :send_message action as the button)' do
    visit '/docs/example-chat'

    within first("[data-testid='live-example-demo']") do
      find("[data-testid='chat-input']").set('sent with the enter key')
      find("[data-testid='chat-input']").send_keys(:enter)

      expect(page).to have_css("[data-testid='message-body']", text: 'sent with the enter key')
      expect(page).to have_field('body', with: '')
    end

    expect(ChatMessage.where(body: 'sent with the enter key')).to exist
  end
end
