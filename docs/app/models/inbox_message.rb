# frozen_string_literal: true

class InboxMessage < ApplicationRecord
  validates :subject, presence: true

  scope :active, -> { order(read: :asc, created_at: :desc, id: :desc) }

  # The shared stream the inbox broadcasts archive/mark-read over, so two open
  # tabs (teammates on the same inbox) stay in sync.
  def self.stream_key = %w[team-inbox all]
end
