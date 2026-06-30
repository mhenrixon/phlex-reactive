# frozen_string_literal: true

require 'rails_helper'
require 'turbo/broadcastable/test_helper'

# The server->client half: a reactive action that broadcasts. We assert the
# Turbo Stream is broadcast to the room's stream — transport-agnostic (Action
# Cable here, pgbus in a real app).
RSpec.describe 'Chat broadcast', type: :request do
  # ActionCable's broadcast assertions call _assert_nothing_raised_or_warn from
  # ActiveSupport::Testing::Assertions, which rspec-rails doesn't mix in by default.
  include ActiveSupport::Testing::Assertions
  include Turbo::Broadcastable::TestHelper

  def send_message(room:, body:)
    token = Phlex::Reactive.sign(
      'c' => 'ChatComposerComponent',
      's' => { 'room' => room, 'author' => 'tester' }
    )
    post '/reactive/actions',
         params: { token:, act: 'send_message', params: { body: } }.to_json,
         headers: { 'Content-Type' => 'application/json', 'Accept' => 'text/vnd.turbo-stream.html' }
  end

  it 'creates the message and broadcasts it to the room stream' do
    assert_turbo_stream_broadcasts(ChatMessage.stream_key('lobby'), count: 1) do
      send_message(room: 'lobby', body: 'hello room')
    end

    expect(response).to have_http_status(:ok)
    expect(ChatMessage.where(room: 'lobby', body: 'hello room')).to exist
  end

  it "broadcasts an append targeting the room's message list" do
    broadcasts = capture_turbo_stream_broadcasts(ChatMessage.stream_key('lobby')) do
      send_message(room: 'lobby', body: 'targeted')
    end

    html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
    expect(html).to include('action="append"')
    expect(html).to include('target="chat-messages-lobby"')
    expect(html).to include('targeted')
  end

  it 'does not broadcast a blank message' do
    assert_no_turbo_stream_broadcasts(ChatMessage.stream_key('lobby')) do
      send_message(room: 'lobby', body: '   ')
    end
    expect(ChatMessage.count).to eq(0)
  end

  it 'forbids an undeclared action' do
    token = Phlex::Reactive.sign('c' => 'ChatComposerComponent', 's' => { 'room' => 'lobby', 'author' => 'x' })
    post '/reactive/actions',
         params: { token:, act: 'delete_all', params: {} }.to_json,
         headers: { 'Content-Type' => 'application/json', 'Accept' => 'text/vnd.turbo-stream.html' }
    expect(response).to have_http_status(:forbidden)
  end
end
