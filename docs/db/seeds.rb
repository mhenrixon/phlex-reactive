# frozen_string_literal: true

# Idempotent demo seed data so the deployed docs site has something to show in
# the record-backed demos (Todos, Chat). Safe to run on every boot.
if Todo.none?
  ['Try the searchable combobox', 'Toggle me done', 'Rename me inline'].each do |title|
    Todo.create!(title:)
  end
end

if Notification.none?
  ['Your build passed', 'New comment on your PR', 'Deploy to staging finished'].each do |title|
    Notification.create!(title:)
  end
end

if InboxMessage.none?
  [
    { subject: 'Deploy to production finished', sender: 'ci' },
    { subject: 'New signup: acme.co', sender: 'billing' },
    { subject: 'Locked: compliance hold', sender: 'locked' }, # archive denies → optimistic revert demo
    { subject: 'Weekly digest', sender: 'system', read: true }
  ].each { |attrs| InboxMessage.create!(**attrs) }
end

if ChatMessage.where(room: 'lobby').none?
  [
    { author: 'ruby', body: 'Welcome to the phlex-reactive chat demo!' },
    { author: 'you', body: 'Send a message — it broadcasts with zero custom JS.' }
  ].each { |attrs| ChatMessage.create!(room: 'lobby', **attrs) }
end
