# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleChat < Views::Docs::Page
        title 'Cross-tab chat (the showcase)'
        eyebrow 'Examples'

        def lead
          'A live chat where a message typed in one tab appears instantly in every other tab and browser — ' \
            'no login, no Action Cable, no Redis, and no JavaScript you write.'
        end

        def content
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

        def intro
          render Views::Docs::Section.new('The example that proves the model') do
            render Views::Docs::Prose.new do
              p do
                plain 'This is the example that proves the whole model: a client '
                strong { 'action' }
                plain ' (send) and a server '
                strong { 'broadcast' }
                plain ' (fan-out) both reduce to “render this component into the DOM by its id.” '
                plain 'About 60 lines of Ruby, end to end.'
              end
            end
          end
        end

        def model
          render Views::Docs::Section.new('1. Model') do
            render Views::Code.new(<<~RUBY, lexer: :ruby, filename: 'app/models/chat_message.rb')
              class ChatMessage < ApplicationRecord
                validates :body, presence: true
                scope :for_room, ->(room) { where(room:).order(:created_at, :id) }

                # The stream key both subscribers and broadcasters agree on for a room.
                def self.stream_key(room) = Pgbus.stream_key("chat", room)
              end
            RUBY
            render Views::Code.new(<<~RUBY, lexer: :ruby, filename: 'db/migrate/XXXX_create_chat_messages.rb')
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
          render Views::Docs::Section.new('2. One message (record-backed, self-targeting)') do
            render Views::Code.new(<<~RUBY, lexer: :ruby, filename: 'app/components/chat/message.rb')
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
          end
        end

        def composer
          render Views::Docs::Section.new('3. The composer (a reactive action that creates + broadcasts)') do
            render Views::Code.new(<<~RUBY, lexer: :ruby, filename: 'app/components/chat/composer.rb')
              class Chat::Composer < ApplicationComponent
                include Phlex::Reactive::Streamable
                include Phlex::Reactive::Component

                reactive_state :room, :author          # record-less: signed state is the room/author
                action :send_message, params: { body: :string }

                def initialize(room: "lobby", author: nil)
                  @room = room
                  @author = author.presence || "anon-\#{rand(1000)}"
                end

                def id = "chat-composer-\#{@room}"

                def send_message(body:)
                  body = body.to_s.strip
                  return if body.blank?

                  message = ChatMessage.create!(room: @room, author: @author, body:)

                  # Cross-tab fan-out over pgbus SSE. Append the rendered message to the
                  # #chat-messages-<room> list in EVERY subscribed tab/browser.
                  #
                  # Pass RAW key parts ("chat", room). broadcast_append_to builds the stream
                  # key itself; passing an already-built "chat:lobby" double-keys it.
                  Chat::Message.broadcast_append_to(
                    "chat", @room,
                    target: "chat-messages-\#{@room}",
                    model: message
                  )
                end

                def view_template
                  div(**reactive_root(class: "composer")) do
                    input(type: "text", name: "body", placeholder: "Message as \#{@author}…", autocomplete: "off")
                    button(**on(:send_message)) { "Send" }
                  end
                end
              end
            RUBY
            render Views::Docs::Prose.new do
              p do
                plain 'The Stimulus runtime auto-collects the '
                code { 'name="body"' }
                plain ' field on the button click, so the action receives '
                code { 'body:' }
                plain ' with no '
                code { '<form>' }
                plain ' and no '
                code { 'data-*' }
                plain ' plumbing.'
              end
            end
          end
        end

        def room
          render Views::Docs::Section.new('4. The room (subscribe + list + composer)') do
            render Views::Code.new(<<~RUBY, lexer: :ruby, filename: 'app/components/chat/room.rb')
              class Chat::Room < ApplicationComponent
                def initialize(room: "lobby", messages: [])
                  @room = room
                  @messages = messages
                end

                def view_template
                  div(class: "chat") do
                    turbo_stream_from ChatMessage.stream_key(@room)   # pgbus SSE subscribe

                    div(id: "chat-messages-\#{@room}", class: "messages") do
                      @messages.each { |m| render Chat::Message.new(chat_message: m) }
                    end

                    render Chat::Composer.new(room: @room)
                  end
                end
              end
            RUBY
          end
        end

        def controller
          render Views::Docs::Section.new('5. Controller + route (no auth, for the demo)') do
            render Views::Code.new(<<~RUBY, lexer: :ruby, filename: 'config/routes.rb')
              get "chat" => "chats#show"
            RUBY
            render Views::Code.new(<<~RUBY, lexer: :ruby, filename: 'app/controllers/chats_controller.rb')
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
          render Views::Docs::Section.new('What happens when you click Send') do
            render Views::Docs::Prose.new do
              ol do
                li do
                  plain 'The '
                  code { 'reactive' }
                  plain ' controller serializes '
                  code { '{ token, act: "send_message", params: { body } }' }
                  plain ' and POSTs to '
                  code { '/reactive/actions' }
                  plain '.'
                end
                li do
                  plain 'The endpoint verifies the signed token, rebuilds the composer, and runs ' \
                        'send_message inside a transaction.'
                end
                li do
                  plain 'send_message creates the '
                  code { 'ChatMessage' }
                  plain ' and calls '
                  code { 'broadcast_append_to' }
                  plain '.'
                end
                li do
                  plain 'pgbus fans the rendered '
                  code { 'Chat::Message' }
                  plain ' out over SSE to every subscribed '
                  code { '<pgbus-stream-source>' }
                  plain ' — including the sender’s other tabs.'
                end
                li do
                  plain 'Each tab’s Turbo appends it to '
                  code { '#chat-messages-<room>' }
                  plain '. Idiomorph dedupes by DOM id, so the sender doesn’t get a duplicate.'
                end
                li { plain 'The action’s own response re-renders the composer (clearing the input).' }
              end
            end
          end
        end

        def why_better
          render Views::Docs::Section.new('Why this is better than the Hotwire version') do
            render Views::Docs::Prose.new do
              ul do
                li do
                  strong { 'No Stimulus controller, no Action Cable channel, no Redis.' }
                end
                li do
                  strong { 'Transactional' }
                  plain ': if '
                  code { 'create!' }
                  plain ' or the broadcast raised, the transaction rolls back — no half-sent message, ' \
                        'no ghost broadcast.'
                end
                li do
                  strong { 'Reconnect-safe' }
                  plain ': a tab that was briefly offline replays the messages it missed '
                  plain '(pgbus '
                  code { 'Last-Event-ID' }
                  plain ' + PGMQ archive).'
                end
                li { plain 'The new code is less than the Stimulus controller alone would have been.' }
              end
            end
          end
        end

        def going_further
          render Views::Docs::Section.new('Going further') do
            render Views::Docs::Prose.new do
              ul do
                li do
                  strong { 'Authenticated chat' }
                  plain ': drop '
                  code { 'reactive_state :author' }
                  plain ', set '
                  code { '@author' }
                  plain ' from '
                  code { 'current_user' }
                  plain ', and authorize in send_message.'
                end
                li do
                  strong { 'Per-user rooms' }
                  plain ': '
                  code { 'turbo_stream_from ChatMessage.stream_key(current_user)' }
                  plain ' and broadcast to the same key.'
                end
                li do
                  strong { 'Typing indicators / presence' }
                  plain ': use pgbus presence ('
                  code { 'Pgbus.stream(...).presence.join/leave' }
                  plain ').'
                end
              end
            end
            render Views::Docs::Callout.new(:tip) do
              plain 'No login, no Action Cable, no Redis, no JavaScript you write — and the new code is ' \
                    'less than the Stimulus controller alone would have been.'
            end
          end
        end
      end
    end
  end
end
