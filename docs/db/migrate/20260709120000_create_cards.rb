# frozen_string_literal: true

class CreateCards < ActiveRecord::Migration[8.1]
  def change
    create_table :cards do |t|
      t.string :title, null: false
      t.string :lane, null: false, default: 'todo'
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
