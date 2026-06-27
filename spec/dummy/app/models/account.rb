# frozen_string_literal: true

# Owner of a has_one :address, edited inline via the nested-attributes helper
# (issue #24). update_only: true means Rails matches the existing address by id
# rather than building a second one — which is exactly the id preservation the
# nested_update! helper automates.
class Account < ActiveRecord::Base
  has_one :address, dependent: :destroy
  accepts_nested_attributes_for :address, update_only: true

  validates :name, presence: true
end
