# frozen_string_literal: true

class ChatMessage < ActiveRecord::Base
  validates :body, presence: true
  # Named arg required: `where(room:)` kwarg-shorthand needs a local `room`; `it`
  # would become `where(it:)` (wrong key). rubocop:disable Style/ItBlockParameter
  scope :for_room, ->(room) { where(room:).order(:created_at, :id) } # rubocop:disable Style/ItBlockParameter

  def self.stream_key(room) = ["chat", room]
end
