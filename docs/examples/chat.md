---
layout: default
title: Cross-tab chat
parent: Examples
nav_order: 2
---

# Example: cross-tab chat (the showcase)

A live chat where a message typed in one tab appears instantly in every other
tab and browser — no login, no Action Cable, no Redis, **no JavaScript you
write**. This is the example that proves the whole model: a client *action*
(send) and a server *broadcast* (fan-out) both reduce to "render this component
into the DOM by its id."

~60 lines of Ruby. Here it is end to end.

## 1. Model

```ruby
# app/models/chat_message.rb
class ChatMessage < ApplicationRecord
  validates :body, presence: true
  scope :for_room, ->(room) { where(room:).order(:created_at, :id) }

  # The stream key both subscribers and broadcasters agree on for a room.
  def self.stream_key(room) = Pgbus.stream_key("chat", room)
end
```

```ruby
# db/migrate/XXXX_create_chat_messages.rb
create_table :chat_messages do |t|
  t.string :room,   null: false, default: "lobby"
  t.string :author, null: false, default: "anon"
  t.text   :body,   null: false
  t.timestamps
end
add_index :chat_messages, %i[room created_at]
```

## 2. One message (record-backed, self-targeting)

```ruby
# app/components/chat/message.rb
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
```

## 3. The composer (a reactive action that creates + broadcasts)

```ruby
# app/components/chat/composer.rb
class Chat::Composer < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

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

    # Cross-tab fan-out over pgbus SSE. Append the rendered message to the
    # #chat-messages-<room> list in EVERY subscribed tab/browser.
    #
    # Pass RAW key parts ("chat", room). broadcast_append_to builds the stream
    # key itself; passing an already-built "chat:lobby" double-keys it.
    Chat::Message.broadcast_append_to(
      "chat", @room,
      target: "chat-messages-#{@room}",
      model: message
    )
  end

  def view_template
    div(**reactive_root(class: "composer")) do
      input(type: "text", name: "body", placeholder: "Message as #{@author}…", autocomplete: "off")
      button(**on(:send_message)) { "Send" }
    end
  end
end
```

The Stimulus runtime auto-collects the `name="body"` field on the button click,
so the action receives `body:` with no `<form>` and no `data-*` plumbing.

## 4. The room (subscribe + list + composer)

```ruby
# app/components/chat/room.rb
class Chat::Room < ApplicationComponent
  def initialize(room: "lobby", messages: [])
    @room = room
    @messages = messages
  end

  def view_template
    div(class: "chat") do
      turbo_stream_from ChatMessage.stream_key(@room)   # pgbus SSE subscribe

      div(id: "chat-messages-#{@room}", class: "messages") do
        @messages.each { |m| render Chat::Message.new(chat_message: m) }
      end

      render Chat::Composer.new(room: @room)
    end
  end
end
```

## 5. Controller + route (no auth, for the demo)

```ruby
# config/routes.rb
get "chat" => "chats#show"

# app/controllers/chats_controller.rb
class ChatsController < ApplicationController
  def show
    room = params[:room].presence || "lobby"
    render Chat::Room.new(room:, messages: ChatMessage.for_room(room).last(50))
  end
end
```

## What happens when you click Send

1. The `reactive` controller serializes `{ token, act: "send_message",
   params: { body } }` and POSTs to `/reactive/actions`.
2. The endpoint verifies the signed token, rebuilds the composer, runs
   `send_message` inside a transaction.
3. `send_message` creates the `ChatMessage` and calls `broadcast_append_to`.
4. pgbus fans the rendered `Chat::Message` out over SSE to **every** subscribed
   `<pgbus-stream-source>` — including the sender's other tabs.
5. Each tab's Turbo appends it to `#chat-messages-<room>`. Idiomorph dedupes by
   DOM id, so the sender doesn't get a duplicate.
6. The action's own response re-renders the composer (clearing the input).

## Why this is better than the Hotwire version

- **No Stimulus controller, no Action Cable channel, no Redis.**
- **Transactional**: if `create!` or the broadcast raised, the transaction rolls
  back — no half-sent message, no ghost broadcast.
- **Reconnect-safe**: a tab that was briefly offline replays the messages it
  missed (pgbus `Last-Event-ID` + PGMQ archive).
- The new code is *less than the Stimulus controller alone* would have been.

## Going further

- **Authenticated chat**: drop `reactive_state :author`, set `@author` from
  `current_user`, and authorize in `send_message`.
- **Per-user rooms**: `turbo_stream_from ChatMessage.stream_key(current_user)`
  and broadcast to the same key.
- **Typing indicators / presence**: use pgbus presence
  (`Pgbus.stream(...).presence.join/leave`). See
  [docs/broadcasting.md](../broadcasting.md).
