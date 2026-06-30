# frozen_string_literal: true

class CreateTodosAndChatMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :todos do |t|
      t.string :title, null: false
      t.boolean :done, null: false, default: false
      t.timestamps
    end

    create_table :chat_messages do |t|
      t.string :room, null: false, default: "lobby"
      t.string :author, null: false, default: "anon"
      t.text :body, null: false
      t.timestamps
    end
  end
end
