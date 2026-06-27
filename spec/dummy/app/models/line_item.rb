# frozen_string_literal: true

# Issue #30: a spreadsheet-like line-item row. quantity × price = total. The
# reactive row saves a field and re-streams ONLY the computed total cell, so the
# sibling field the user is still typing in is never torn down.
class LineItem < ActiveRecord::Base
  def total = quantity * price
end
