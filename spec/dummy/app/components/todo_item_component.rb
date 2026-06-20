# frozen_string_literal: true

# Record-backed reactive row. Exercises reactive_record (GlobalID identity),
# a param action (rename via change), and a toggle.
class TodoItemComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo
  action :toggle
  action :rename, params: {title: :string}

  def initialize(todo:)
    @todo = todo
  end

  def id = dom_id(@todo) # Streamable#dom_id is render-context-free
  def self.model_param_name = :todo

  def toggle
    @todo.update!(done: !@todo.done?)
  end

  def rename(title:)
    @todo.update!(title:) if title.present?
  end

  def view_template
    li(**mix(reactive_attrs, id:, data: {testid: "todo", done: @todo.done?.to_s})) do
      button(**mix(on(:toggle), data: {testid: "toggle"})) { @todo.done? ? "✓" : "○" }
      input(**mix(on(:rename, event: "change"), name: "title", value: @todo.title))
    end
  end
end
