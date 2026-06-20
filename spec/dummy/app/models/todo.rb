# frozen_string_literal: true

class Todo < ActiveRecord::Base
  validates :title, presence: true
end
