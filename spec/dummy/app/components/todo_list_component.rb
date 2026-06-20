# frozen_string_literal: true

# Record-backed list with an `add` action that creates a Todo and appends the
# new row's component (in the action response).
class TodoListComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :build_token # unused placeholder so the list has stable state
  action :add, params: { title: :string }

  def initialize(build_token: "list")
    @build_token = build_token
  end

  def id = "todo-list"

  def add(title:)
    title = title.to_s.strip
    return if title.blank?

    Todo.create!(title:)
  end

  def view_template
    div(id:, **reactive_attrs) do
      ul(id: "todos") do
        Todo.order(:created_at, :id).each { |todo| render TodoItemComponent.new(todo:) }
      end

      div do
        input(name: "title", placeholder: "New todo…", autocomplete: "off", data: { testid: "new-todo" })
        button(**mix(on(:add), data: { testid: "add" })) { "Add" }
      end
    end
  end
end
