# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleChat < DocsUI::Page
        title 'Cross-tab chat (the showcase)'
        eyebrow 'Examples'
        description 'Build a live cross-tab chat in Rails with reactive Phlex components: a record-backed action plus one Turbo Streams broadcast, no Stimulus or Action Cable'

        def lead
          'A live chat where a message typed in one tab appears in every other subscribed tab — ' \
            'a record-backed action plus one broadcast, no Action Cable channel and no JavaScript you write.'
        end

        def content
          try_it
          intro
          model
          message
          composer
          room
          controller
          on_click
          why_better
          going_further
        end

        private

        def try_it
          DocsUI::Section('Try it') do
            md <<~MD
              A **real** chat room, rendered right here. Type a message and Send —
              it creates a `ChatMessage`, appends it to the list, and broadcasts to
              every subscriber over Turbo Streams (open a second tab to watch it
              arrive live). The sender is excluded from the broadcast
              (`exclude: reactive_connection_id`), so Send appends exactly once. No
              Stimulus, no hand-picked Turbo target.
            MD
            render Views::Examples::LiveExample.new(
              component: ChatRoomComponent.new(room: 'lobby', messages: ChatMessage.for_room('lobby').last(50)),
              filename: 'app/components/chat_room_component.rb'
            )
          end
        end

        def intro
          DocsUI::Section('The example that proves the model') do
            md <<~MD
              This is the example that proves the whole model: a client **action**
              (send) and a server **broadcast** (fan-out) both reduce to "render this
              component into the DOM by its id." About 60 lines of Ruby, end to end.

              The one broadcasting detail that makes it correct: the fan-out passes
              `exclude: reactive_connection_id` so the **sender** doesn't get a
              doubled message — the actor already saw it via the action's own HTTP
              reply. That single argument, not any DOM-level dedup, is why a `Send`
              appends exactly once for the person who sent it.
            MD
          end
        end

        def model
          DocsUI::Section('1. Model') do
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/models/chat_message.rb')
              class ChatMessage < ApplicationRecord
                validates :body, presence: true
                scope :for_room, ->(room) { where(room:).order(:created_at, :id) }

                # The RAW stream key parts both subscribers and broadcasters agree on.
                # Return the parts, not a pre-built "chat:lobby" string — both sides
                # splat this so turbo_stream_from and broadcast_append_to build the
                # same key. (Double-keying a pre-built string trips pgbus's separator guard.)
                def self.stream_key(room) = ["chat", room]
              end
            RUBY
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'db/migrate/XXXX_create_chat_messages.rb')
              create_table :chat_messages do |t|
                t.string :room,   null: false, default: "lobby"
                t.string :author, null: false, default: "anon"
                t.text   :body,   null: false
                t.timestamps
              end
              add_index :chat_messages, %i[room created_at]
            RUBY
          end
        end

        def message
          DocsUI::Section('2. One message (record-backed, self-targeting)') do
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/components/chat/message.rb')
              class Chat::Message < ApplicationComponent
                include Phlex::Reactive::Streamable

                def initialize(chat_message:) = @message = chat_message
                def id = dom_id(@message)              # stable id == broadcast target
                def self.model_param_name = :chat_message

                def view_template
                  div(id:, class: "msg") do
                    div(class: "author") { @message.author }
                    div(class: "body")   { @message.body }
                    div(class: "time")   { @message.created_at.strftime("%H:%M:%S") }
                  end
                end
              end
            RUBY
            md <<~MD
              The message is broadcast-only, so it includes just
              `Phlex::Reactive::Streamable` and hand-writes `#id` and
              `.model_param_name`. A full `Phlex::Reactive::Component` (the composer
              below) would get `dom_id(record)` as its `#id` for free (issue #81) —
              here we spell it out because a `Streamable`-only class has no
              `reactive_record` to derive it from.
            MD
          end
        end

        def composer
          DocsUI::Section('3. The composer (a reactive action that creates + broadcasts)') do
            DocsUI::Code(<<~'RUBY', lexer: :ruby, filename: 'app/components/chat/composer.rb')
              class Chat::Composer < ApplicationComponent
                include Phlex::Reactive::Component     # pulls in Streamable too

                reactive_state :room, :author          # record-less: signed state is the room/author
                action :send_message, params: { body: :string }

                def initialize(room: "lobby", author: nil)
                  @room = room
                  @author = author.presence || "anon-#{rand(1000)}"
                end

                def id = "chat-composer-#{@room}"

                def send_message(body:)
                  body = body.to_s.strip
                  return if body.blank?

                  message = ChatMessage.create!(room: @room, author: @author, body:)

                  # Fan-out: append the rendered message to #chat-messages-<room> in
                  # every subscribed tab. Splat the RAW key parts so subscribe and
                  # broadcast agree; exclude the actor's own connection so the SENDER
                  # doesn't get a doubled message (they already got the action's reply).
                  Chat::Message.broadcast_append_to(
                    *ChatMessage.stream_key(@room),
                    target: "chat-messages-#{@room}",
                    model: message,
                    exclude: reactive_connection_id      # suppress the actor's own echo
                  )
                end

                def view_template
                  div(**reactive_root(class: "composer")) do
                    input(type: "text", name: "body", placeholder: "Message as #{@author}…", autocomplete: "off")
                    button(**on(:send_message)) { "Send" }
                  end
                end
              end
            RUBY
            md <<~MD
              The Stimulus runtime auto-collects the `name="body"` field on the button
              click, so the action receives `body:` with no `<form>` and no `data-*`
              plumbing.

              **`exclude: reactive_connection_id` is the whole point of this example.**
              An append *inserts* a new child into the messages container — it is not
              id-deduped the way a `replace`/`morph` of an existing element is. Without
              `exclude:`, the sender's own subscribed tab would receive the broadcast
              and append the message a **second** time, on top of the copy the action
              reply already rendered. `exclude:` names the actor's connection so the
              broadcast reaches everyone *but* them. It's a **transport** option
              (`exclude:` / `visible_to:`) forwarded to pgbus — with the plain Action
              Cable adapter it's ignored (see the room's note).
            MD
          end
        end

        def room
          DocsUI::Section('4. The room (subscribe + list + composer)') do
            DocsUI::Code(<<~'RUBY', lexer: :ruby, filename: 'app/components/chat/room.rb')
              class Chat::Room < ApplicationComponent
                def initialize(room: "lobby", messages: [])
                  @room = room
                  @messages = messages
                end

                def view_template
                  div(class: "chat") do
                    # Splat the RAW key parts — the SAME parts the composer broadcasts to.
                    turbo_stream_from(*ChatMessage.stream_key(@room))

                    div(id: "chat-messages-#{@room}", class: "messages") do
                      @messages.each { |m| render Chat::Message.new(chat_message: m) }
                    end

                    render Chat::Composer.new(room: @room)
                  end
                end
              end
            RUBY
            DocsUI::Callout(:note) do
              md <<~MD
                **This docs site's live demo runs on the in-process async Action Cable
                adapter, not pgbus.** So the transactional guarantee and
                `exclude:` / `visible_to:` scoping are inert on the running demo, and
                true cross-*browser* delivery needs a real pub/sub backend (Redis or
                pgbus). Wire pgbus in a real app and the *same* code above becomes
                transactional, reconnect-safe, and honors `exclude:`. See
                [Broadcasting & live updates](/docs/broadcasting).
              MD
            end
          end
        end

        def controller
          DocsUI::Section('5. Controller + route (no auth, for the demo)') do
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'config/routes.rb')
              get "chat" => "chats#show"
            RUBY
            DocsUI::Code(<<~RUBY, lexer: :ruby, filename: 'app/controllers/chats_controller.rb')
              class ChatsController < ApplicationController
                def show
                  room = params[:room].presence || "lobby"
                  render Chat::Room.new(room:, messages: ChatMessage.for_room(room).last(50))
                end
              end
            RUBY
          end
        end

        def on_click
          DocsUI::Section('What happens when you click Send') do
            md <<~MD
              1. The `reactive` controller serializes
                 `{ token, act: "send_message", params: { body } }` and POSTs to
                 `/reactive/actions`.
              2. The endpoint verifies the signed token, rebuilds the composer, and
                 runs `send_message` inside a transaction.
              3. `send_message` creates the `ChatMessage` and calls
                 `broadcast_append_to(..., exclude: reactive_connection_id)`.
              4. The broadcast fans the rendered `Chat::Message` out over the stream
                 transport to every subscribed room — **except** the sender's own
                 connection, which `exclude:` filters out.
              5. Each *other* tab's Turbo appends it to `#chat-messages-<room>`.
              6. The action's own HTTP reply re-renders the composer (clearing the
                 input) for the sender — that reply, not the broadcast, is how the
                 sender sees their own message, so they see it exactly once.
            MD
          end
        end

        def why_better
          DocsUI::Section('Why this is better than the Hotwire version') do
            md <<~MD
              - **No Stimulus controller, no Action Cable channel, no Redis.**
              - **Transactional** (with pgbus): if `create!` or the broadcast raised,
                the transaction rolls back — no half-sent message, no ghost broadcast.
              - **Reconnect-safe** (with pgbus): a tab that was briefly offline replays
                the messages it missed (`Last-Event-ID` + the PGMQ archive).
              - **Actor-correct out of the box:** `exclude: reactive_connection_id`
                suppresses the sender's own echo, so no client-side dedup logic is
                needed.
              - The new code is less than the Stimulus controller alone would have been.
            MD
          end
        end

        def going_further
          DocsUI::Section('Going further') do
            md <<~MD
              - **Authenticated chat:** drop `reactive_state :author`, set `@author`
                from `current_user`, and authorize in `send_message`.
              - **Per-user rooms:** `turbo_stream_from(*ChatMessage.stream_key(current_user))`
                and broadcast to the same raw parts.
              - **Scope who sees a broadcast:** pass `visible_to:` alongside `exclude:`
                — the transport-level companion for delivering a message to only some
                connections (honored on pgbus). See
                [Broadcasting & live updates](/docs/broadcasting).
              - **Typing indicators / presence:** use pgbus presence
                (`Pgbus.stream(...).presence.join/leave`).
            MD
            DocsUI::Callout(:tip) do
              plain 'No login, no Action Cable channel, no Redis, no JavaScript you write — and the new code ' \
                    'is less than the Stimulus controller alone would have been.'
            end
          end
        end
      end
    end
  end
end
