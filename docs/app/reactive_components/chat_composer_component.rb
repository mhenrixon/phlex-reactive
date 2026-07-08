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
    target = "chat-messages-#{@room}"
    # Broadcast the new message to every OTHER subscribed tab — excluding the
    # actor's own connection so they don't get it twice (the reply below already
    # appends it for the sender).
    ChatMessageComponent.broadcast_to(
      *ChatMessage.stream_key(@room),
      append: message,
      target:,
      exclude: reactive_connection_id
    )
    # Append the message to the SENDER's own list via their reply — the composer's
    # root doesn't own #chat-messages (it's in the parent room), and the broadcast
    # excludes the actor, so without this the sender's own message never appears.
    # Mirrors the todo `add` / inbox `archive` pattern: actor via reply, others via
    # the excluded broadcast. reply.replace re-renders the composer (clears the
    # input); .stream adds the cross-container append targeting the room's list.
    reply.replace.stream(ChatMessageComponent.append(target:, model: message))
  end

  def view_template
    div(**mix(reactive_root, class: 'flex gap-2')) do
      # Enter in the field sends — the same :send_message action the button fires
      # on click. event: "keydown.enter" is Stimulus's native keyboard filter, so
      # only Enter dispatches. The field's value rides as the `body` param.
      input(**mix(on(:send_message, event: 'keydown.enter'),
                  type: 'text', name: 'body', placeholder: "Message as #{@author}…",
                  autocomplete: 'off', class: 'input input-bordered flex-1',
                  data: { testid: 'chat-input' }))
      button(**mix(on(:send_message), class: 'btn btn-primary',
                                      data: { testid: 'chat-send' })) { 'Send' }
    end
  end
end
