# frozen_string_literal: true

class Todo < ApplicationRecord
  validates :title, presence: true
end
