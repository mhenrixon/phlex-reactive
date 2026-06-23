# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

# Verifies the server->client half: a reactive action that broadcasts. We assert
# the Turbo Stream is broadcast to the room's stream (the cross-tab fan-out),
# which is transport-agnostic — it works the same whether the transport is
# Action Cable (here) or pgbus (in a real app).
RSpec.describe "Chat broadcast", type: :request do
  include Turbo::Broadcastable::TestHelper

  def send_message(room:, body:, connection: nil)
    token = Phlex::Reactive.sign(
      "c" => "ChatComposerComponent",
      "s" => {"room" => room, "author" => "tester"}
    )
    headers = {"Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html"}
    headers["X-Pgbus-Connection"] = connection if connection
    post "/reactive/actions",
      params: {token:, act: "send_message", params: {body:}}.to_json,
      headers: headers
  end

  it "creates the message and broadcasts it to the room stream" do
    stream = ChatMessage.stream_key("lobby")

    assert_turbo_stream_broadcasts(stream, count: 1) do
      send_message(room: "lobby", body: "hello room")
    end

    expect(response).to have_http_status(:ok)
    expect(ChatMessage.where(room: "lobby", body: "hello room")).to exist
  end

  it "broadcasts an append targeting the room's message list" do
    broadcasts = capture_turbo_stream_broadcasts(ChatMessage.stream_key("lobby")) do
      send_message(room: "lobby", body: "targeted")
    end

    # broadcasts are parsed nodes, not strings; stringify before joining.
    html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
    expect(html).to include('action="append"')
    expect(html).to include('target="chat-messages-lobby"')
    expect(html).to include("targeted")
  end

  it "does not broadcast a blank message" do
    assert_no_turbo_stream_broadcasts(ChatMessage.stream_key("lobby")) do
      send_message(room: "lobby", body: "   ")
    end
    expect(ChatMessage.count).to eq(0)
  end

  describe "actor-echo suppression (exclude:)" do
    it "passes the X-Pgbus-Connection header through to the broadcast as exclude:" do
      allow(ChatMessageComponent).to receive(:broadcast_append_to)

      send_message(room: "lobby", body: "hi", connection: "conn-actor-123")

      expect(ChatMessageComponent).to have_received(:broadcast_append_to)
        .with("chat", "lobby", hash_including(exclude: "conn-actor-123"))
    end

    it "broadcasts with exclude: nil when no connection header is present" do
      allow(ChatMessageComponent).to receive(:broadcast_append_to)

      send_message(room: "lobby", body: "hi")

      expect(ChatMessageComponent).to have_received(:broadcast_append_to)
        .with("chat", "lobby", hash_including(exclude: nil))
    end

    it "clears the connection id after the action (no leak across requests)" do
      send_message(room: "lobby", body: "first", connection: "conn-1")
      expect(Phlex::Reactive.current_connection_id).to be_nil
    end
  end
end
