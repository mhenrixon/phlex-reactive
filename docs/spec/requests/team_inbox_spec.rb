# frozen_string_literal: true

require 'rails_helper'
require 'turbo/broadcastable/test_helper'

# The flagship Team inbox: reactive_collection archive/mark-read/simulate, cross-tab
# broadcasts, and a denied archive of a locked message (optimistic revert).
RSpec.describe 'Team inbox actions', type: :request do
  include ActiveSupport::Testing::Assertions
  include Turbo::Broadcastable::TestHelper

  def inbox_payload = { 's' => {} }

  describe '#archive' do
    let!(:message) { InboxMessage.create!(subject: 'Deploy finished', sender: 'ci') }

    it 'removes the row + count + empty and confirms with a self-dismissing flash' do
      expect do
        post_action(TeamInboxComponent, payload: inbox_payload, act: 'archive', params: { id: message.id })
      end.to change(InboxMessage, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="remove"')
      expect(response.body).to include('inbox-count')
      expect(response.body).to include('data-reactive-dismiss-after="2000"')
    end

    it 'broadcasts the removal to teammates' do
      broadcasts = capture_turbo_stream_broadcasts(InboxMessage.stream_key) do
        post_action(TeamInboxComponent, payload: inbox_payload, act: 'archive', params: { id: message.id })
      end
      html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="remove"')
    end
  end

  describe '#archive on a locked message (optimistic revert)' do
    let!(:locked) { InboxMessage.create!(subject: 'Compliance hold', sender: 'locked') }

    it 'denies with a 403 and does NOT destroy the record' do
      expect do
        post_action(TeamInboxComponent, payload: inbox_payload, act: 'archive', params: { id: locked.id })
      end.not_to change(InboxMessage, :count)

      expect(response).to have_http_status(:forbidden)
      # error_flash surfaces the reason; the client reverts the optimistic hide.
      expect(response.body).to include('Something went wrong')
    end
  end

  describe '#mark_read' do
    let!(:message) { InboxMessage.create!(subject: 'New signup', sender: 'billing', read: false) }

    it 'marks the message read and re-renders' do
      post_action(TeamInboxComponent, payload: inbox_payload, act: 'mark_read', params: { id: message.id })
      expect(message.reload.read?).to be(true)
      expect(response).to have_http_status(:ok)
    end
  end

  describe '#simulate_incoming' do
    it 'creates a message and appends the row + count' do
      expect do
        post_action(TeamInboxComponent, payload: inbox_payload, act: 'simulate_incoming')
      end.to change(InboxMessage, :count).by(1)

      expect(response.body).to include('target="inbox-messages"')
    end
  end

  it 'forbids an undeclared action (default-deny)' do
    post_action(TeamInboxComponent, payload: inbox_payload, act: 'delete_all')
    expect(response).to have_http_status(:forbidden)
  end
end
