# frozen_string_literal: true

require 'rails_helper'
require 'turbo/broadcastable/test_helper'

# The live notification bell: a simulate_event action bumps the unread count,
# re-renders the bell, and broadcasts both the replaced bell and a broadcast_js_to
# pulse to the other tabs.
RSpec.describe 'Notification bell actions', type: :request do
  include ActiveSupport::Testing::Assertions
  include Turbo::Broadcastable::TestHelper

  def simulate(unread: 0)
    post_action(NotificationBellComponent, payload: { 's' => { 'unread' => unread } }, act: 'simulate_event')
  end

  it 'bumps the unread count and re-renders the bell' do
    post_action(NotificationBellComponent, payload: { 's' => { 'unread' => 0 } }, act: 'simulate_event')

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('target="notification-bell"')
    expect(response.body).to include('data-testid="bell-count"')
    expect(response.body).to match(/>\s*1\s*</)
  end

  it 'broadcasts the replaced bell + a reactive:js pulse to the stream' do
    broadcasts = capture_turbo_stream_broadcasts(NotificationBellComponent::STREAM) do
      simulate(unread: 2)
    end

    html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
    # The replace carries the bumped count to every subscribed tab.
    expect(html).to include('action="replace"')
    expect(html).to include('target="notification-bell"')
    # The broadcast_js_to nudge ships a whitelisted DOM op (no HTML re-render).
    expect(html).to include('reactive:js')
    expect(html).to include('animate-bounce')
  end

  it 'forbids an undeclared action (default-deny)' do
    post_action(NotificationBellComponent, payload: { 's' => { 'unread' => 0 } }, act: 'spam')
    expect(response).to have_http_status(:forbidden)
  end
end
