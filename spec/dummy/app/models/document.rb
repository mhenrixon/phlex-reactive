# frozen_string_literal: true

# Issue #34: a record an upload component attaches a file to from a reactive
# action. has_one_attached for the single-file path, has_many_attached for the
# multiple-file (`[:file]`) path.
class Document < ActiveRecord::Base
  has_one_attached :file
  has_many_attached :pages
end
