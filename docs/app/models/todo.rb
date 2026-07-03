# frozen_string_literal: true

class Todo < ApplicationRecord
  validates :title, presence: true

  # The single stream every todo change broadcasts on. A real app would scope
  # this to the owning record (`[list, :todos]`); the demo keeps one shared list
  # so two open tabs sync with each other.
  def self.stream_key = %w[todos all]
end
