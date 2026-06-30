# frozen_string_literal: true

# The chat room: subscribes to the room's Turbo Stream and renders the existing
# messages + the composer. New messages arrive via broadcast (see
# ChatComposerComponent#send_message), appended live to #chat-messages.
#
# NOTE: this demo runs on the in-process async Action Cable adapter, so live
# updates are same-process. True cross-tab/cross-client delivery needs a real
# pub/sub backend (Redis or pgbus) — out of scope for the demo site.
class ChatRoomComponent < Phlex::HTML
  include Phlex::Rails::Helpers::TurboStreamFrom

  def initialize(room: 'lobby', messages: [])
    @room = room
    @messages = messages
  end

  def view_template
    div(class: 'flex flex-col gap-3') do
      turbo_stream_from(*ChatMessage.stream_key(@room))

      div(id: "chat-messages-#{@room}",
          class: 'flex flex-col gap-1 min-h-32 max-h-80 overflow-y-auto',
          data: { testid: 'chat-messages' }) do
        @messages.each { render ChatMessageComponent.new(chat_message: it) }
      end

      render ChatComposerComponent.new(room: @room)
    end
  end
end
