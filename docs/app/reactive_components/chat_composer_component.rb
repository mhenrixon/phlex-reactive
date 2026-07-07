# frozen_string_literal: true

# Reactive composer: send_message creates a ChatMessage and broadcasts it to the
# room over the stream transport (Action Cable here; pgbus in a real app). The
# action re-renders the composer (cleared input); the broadcast appends the new
# message to every subscriber, excluding the actor's own connection so the sender
# doesn't get a duplicate echo.
class ChatComposerComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :room, :author
  action :send_message, params: { body: :string }

  def initialize(room: 'lobby', author: nil)
    @room = room
    @author = author.presence || 'anon'
  end

  def id = "chat-composer-#{@room}"

  def send_message(body:)
    body = body.to_s.strip
    return if body.blank?

    message = ChatMessage.create!(room: @room, author: @author, body:)
    ChatMessageComponent.broadcast_to(
      *ChatMessage.stream_key(@room),
      append: message,
      target: "chat-messages-#{@room}",
      exclude: reactive_connection_id # suppress the actor's own echo
    )
  end

  def view_template
    div(**mix(reactive_root, class: 'flex gap-2')) do
      input(type: 'text', name: 'body', placeholder: "Message as #{@author}…",
            autocomplete: 'off', class: 'input input-bordered flex-1',
            data: { testid: 'chat-input' })
      button(**mix(on(:send_message), class: 'btn btn-primary',
                                      data: { testid: 'chat-send' })) { 'Send' }
    end
  end
end
