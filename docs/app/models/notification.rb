# frozen_string_literal: true

class Notification < ApplicationRecord
  validates :title, presence: true

  # The single stream notification add/dismiss broadcasts on, so two open tabs
  # (or the badge on another page) stay in sync.
  def self.stream_key = %w[notifications all]
end
