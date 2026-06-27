# frozen_string_literal: true

# Loaded by the test suite to build the in-memory SQLite schema for the dummy
# app's example models. Kept hand-written (no migrations) — this is a test
# harness, not a real app.
ActiveRecord::Schema.define(version: 1) do
  create_table :counters, force: true do |t|
    t.integer :value, null: false, default: 0
    t.timestamps
  end

  create_table :todos, force: true do |t|
    t.string :title, null: false
    t.boolean :done, null: false, default: false
    t.timestamps
  end

  create_table :chat_messages, force: true do |t|
    t.string :room, null: false, default: "lobby"
    t.string :author, null: false, default: "anon"
    t.text :body, null: false
    t.timestamps
  end

  # Owner + has_one association for the accepts_nested_attributes_for helper
  # (issue #24): an Account that edits its Address inline via nested_update!.
  create_table :accounts, force: true do |t|
    t.string :name, null: false
    t.timestamps
  end

  create_table :addresses, force: true do |t|
    t.references :account, null: false
    t.string :street
    t.string :city
    t.string :postal_code
    t.string :country
    t.timestamps
  end

  # Issue #30: a spreadsheet-like line-item row (quantity × price = total). A
  # debounced reactive save updates ONLY the total cell via reply.streams, so the
  # sibling input the user is typing in is never torn down.
  create_table :line_items, force: true do |t|
    t.integer :quantity, null: false, default: 0
    t.integer :price, null: false, default: 0
    t.timestamps
  end
end
