# frozen_string_literal: true

# One chat message — record-backed, self-targeting, broadcastable.
class ChatMessageComponent < ApplicationComponent
  include Phlex::Reactive::Streamable

  def initialize(chat_message:)
    @message = chat_message
  end

  def id = dom_id(@message) # Streamable#dom_id is render-context-free
  def self.model_param_name = :chat_message

  def view_template
    div(id:, class: "msg", data: {testid: "message"}) do
      span(class: "author") { @message.author }
      span(class: "body") { @message.body }
    end
  end
end
