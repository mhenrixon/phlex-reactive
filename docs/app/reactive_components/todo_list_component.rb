# frozen_string_literal: true

# Record-backed list with an `add` action that creates a Todo and appends the
# new row's component in the action response. Each row is its own reactive
# component (TodoItemComponent), self-targeting by GlobalID.
class TodoListComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :build_token # stable placeholder state for the list root
  action :add, params: { title: :string }

  def initialize(build_token: 'list')
    @build_token = build_token
  end

  def id = 'todo-list'

  def add(title:)
    title = title.to_s.strip
    return if title.blank?

    Todo.create!(title:)
  end

  def view_template
    div(**reactive_root(class: 'flex flex-col gap-3')) do
      ul(id: 'todos', class: 'flex flex-col') do
        Todo.order(:created_at, :id).each { render TodoItemComponent.new(todo: it) }
      end

      div(class: 'flex gap-2') do
        input(name: 'title', placeholder: 'New todo…', autocomplete: 'off',
              class: 'input input-bordered flex-1', data: { testid: 'new-todo' })
        button(**mix(on(:add), class: 'btn btn-primary', data: { testid: 'add' })) { 'Add' }
      end
    end
  end
end
