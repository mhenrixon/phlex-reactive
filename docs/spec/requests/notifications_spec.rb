# frozen_string_literal: true

require 'rails_helper'

# reactive_collection (issue #35): the list declares the contract once, and add /
# dismiss emit the row + count + empty-state toggle as ONE reply each. State-backed
# — the size resolver reads the live DB count.
RSpec.describe 'Notifications collection', type: :request do
  def list_payload = { 's' => {} }

  describe '#add' do
    it 'creates a notification and appends the row + count + clears empty' do
      expect do
        post_action(NotificationsListComponent, payload: list_payload,
                                                act: 'add', params: { title: 'Build finished' })
      end.to change(Notification, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Build finished')
      # The collection reply targets the container + the count companion.
      expect(response.body).to include('target="notifications"')
      expect(response.body).to include('notifications-count')
    end

    it 'ignores a blank title' do
      expect do
        post_action(NotificationsListComponent, payload: list_payload, act: 'add', params: { title: '  ' })
      end.not_to change(Notification, :count)
    end
  end

  describe '#dismiss' do
    let!(:notification) { Notification.create!(title: 'Dismiss me') }

    it 'removes the row + count + restores empty, with a self-dismissing flash' do
      expect do
        post_action(NotificationsListComponent, payload: list_payload,
                                                act: 'dismiss', params: { id: notification.id })
      end.to change(Notification, :count).by(-1)

      expect(response.body).to include('action="remove"')
      # The dismiss_after: flash carries the self-dismiss schedule attribute.
      expect(response.body).to include('Notification dismissed')
      expect(response.body).to include('data-reactive-dismiss-after="3000"')
    end
  end

  it 'forbids an undeclared action (default-deny)' do
    post_action(NotificationsListComponent, payload: list_payload, act: 'purge', params: { title: 'x' })
    expect(response).to have_http_status(:forbidden)
  end
end
