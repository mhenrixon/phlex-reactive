# frozen_string_literal: true

# Idempotent demo seed data so the deployed docs site has something to show in
# the record-backed demos (Todos, Chat). Safe to run on every boot.
if Todo.count.zero?
  ["Try the searchable combobox", "Toggle me done", "Rename me inline"].each do |title|
    Todo.create!(title:)
  end
end

if ChatMessage.where(room: "lobby").none?
  [
    { author: "ruby", body: "Welcome to the phlex-reactive chat demo!" },
    { author: "you", body: "Send a message — it broadcasts with zero custom JS." }
  ].each { |attrs| ChatMessage.create!(room: "lobby", **attrs) }
end
