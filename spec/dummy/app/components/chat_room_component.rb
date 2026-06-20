# frozen_string_literal: true

class ChatRoomComponent < ApplicationComponent
  include Phlex::Rails::Helpers::TurboStreamFrom

  def initialize(room: "lobby", messages: [])
    @room = room
    @messages = messages
  end

  def view_template
    div(class: "chat") do
      turbo_stream_from(*ChatMessage.stream_key(@room))

      div(id: "chat-messages-#{@room}", class: "messages") do
        @messages.each { |m| render ChatMessageComponent.new(chat_message: m) }
      end

      render ChatComposerComponent.new(room: @room)
    end
  end
end
