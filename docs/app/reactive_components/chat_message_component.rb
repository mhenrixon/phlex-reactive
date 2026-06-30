# frozen_string_literal: true

# One chat message — record-backed, self-targeting, broadcastable.
class ChatMessageComponent < Phlex::HTML
  include Phlex::Reactive::Streamable

  def initialize(chat_message:)
    @message = chat_message
  end

  # Streamable#dom_id is render-context-free.
  def id = dom_id(@message)
  def self.model_param_name = :chat_message

  def view_template
    div(id:, class: 'chat chat-start', data: { testid: 'message' }) do
      div(class: 'chat-header text-xs opacity-60') { @message.author }
      div(class: 'chat-bubble', data: { testid: 'message-body' }) { @message.body }
    end
  end
end
