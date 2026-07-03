# frozen_string_literal: true

class CreateInboxMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :inbox_messages do |t|
      t.string :subject, null: false
      t.string :sender, null: false, default: 'system'
      t.boolean :read, null: false, default: false

      t.timestamps
    end
  end
end
