# frozen_string_literal: true

# Issue #30: a spreadsheet-like line-item row. quantity × price = total. The
# reactive row saves a field and re-streams ONLY the computed total cell, so the
# sibling field the user is still typing in is never torn down.
class LineItem < ActiveRecord::Base
  # Issue #208: optional — the issue #30 spreadsheet rows are parentless; the
  # draft-order form's rows belong to the order that created them.
  belongs_to :order, optional: true

  def total = quantity * price
end
