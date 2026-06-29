# frozen_string_literal: true

class ChatMessage < ApplicationRecord
  validates :body, presence: true

  scope :for_room, ->(room) { where(room:).order(:created_at, :id) }

  def self.stream_key(room) = ['chat', room]
end
