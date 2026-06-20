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
end
