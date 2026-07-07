# frozen_string_literal: true

# Reactive composer: send_message creates a ChatMessage and broadcasts it to
# the room over the stream transport (Action Cable in the dummy app; pgbus in
# a real app). The action re-renders the composer (cleared input).
class ChatComposerComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :room, :author
  action :send_message, params: { body: :string }

  def initialize(room: "lobby", author: nil)
    @room = room
    @author = author.presence || "anon"
  end

  def id = "chat-composer-#{@room}"

  def send_message(body:)
    body = body.to_s.strip
    return if body.blank?

    message = ChatMessage.create!(room: @room, author: @author, body:)
    # Issue #185: one broadcast_to — the verb (append:) is the kwarg, its value the
    # record payload; target: is the container element, exclude: suppresses the
    # actor's own echo.
    ChatMessageComponent.broadcast_to(
      *ChatMessage.stream_key(@room),
      append: message,
      target: "chat-messages-#{@room}",
      exclude: reactive_connection_id
    )
  end

  def view_template
    div(**mix(reactive_attrs, id:, class: "composer")) do
      input(type: "text", name: "body", placeholder: "Message as #{@author}…", autocomplete: "off", data: { testid: "chat-input" })
      button(**mix(on(:send_message), data: { testid: "chat-send" })) { "Send" }
    end
  end
end
