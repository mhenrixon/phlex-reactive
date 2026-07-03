# frozen_string_literal: true

require 'system_helper'

# The live chat room embedded on the example page: sending a message creates it
# and broadcasts it to the room stream — the same reactive round trip proven on
# /demos/chat, now dogfooded inline on the docs page. (Delivery to the SENDER's
# own tab needs a real pub/sub backend — pgbus in production; the in-process async
# cable this demo runs on fans out cross-CLIENT, so a single session asserts the
# create + the round trip, not a same-tab echo. See the component's own note.)
RSpec.describe 'Chat example page', type: :system do
  before { ChatMessage.delete_all }

  it 'renders the live chat room and sends a message (created + composer clears)' do
    visit '/docs/example-chat'
    page.execute_script("window.__noReload = 'alive'")

    within first("[data-testid='live-example-demo']") do
      expect(page).to have_css("[data-testid='chat-messages']")
      find("[data-testid='chat-input']").set('hello from the docs page')
      find("[data-testid='chat-send']").click

      # The reactive action creates the record and re-renders the composer clear.
      expect(page).to have_field('body', with: '')
    end

    # The message was created and broadcast over the room stream — no full reload.
    expect(page).to have_css("[data-testid='chat-messages']") # still on the page
    expect(ChatMessage.where(body: 'hello from the docs page')).to exist
    expect(page.evaluate_script('window.__noReload')).to eq('alive')
  end
end
