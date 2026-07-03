# frozen_string_literal: true

# The live todo list: a record-backed list whose `add` action creates a Todo,
# appends the new row's component to the actor's own reply, AND broadcasts that
# row to every OTHER subscribed tab so two open windows stay in sync. Each row is
# its own reactive component (TodoItemComponent), self-targeting by GlobalID.
#
# State-backed root (a stable placeholder token) — the rows carry the real record
# identity. `disable_with:` on Add stops a rapid double-click from creating two
# todos, and `on_client` clears the composer with zero round trips.
class TodoListComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component
  include Phlex::Rails::Helpers::TurboStreamFrom

  reactive_state :build_token # stable placeholder state for the list root
  action :add, params: { title: :string }

  def initialize(build_token: 'list')
    @build_token = build_token
  end

  def id = 'todo-list'

  # Create the todo, append the new row to the OTHER tabs, then re-render self so
  # the actor sees the row + the empty-state clears + the composer resets. An
  # append INSERTS a child (not id-deduped like a replace), so exclude: the actor
  # or their own subscribed tab would get the row a second time on top of this
  # self re-render.
  def add(title:)
    title = title.to_s.strip
    return if title.blank?

    todo = Todo.create!(title:)
    TodoItemComponent.broadcast_append_to(*Todo.stream_key, target: 'todos',
                                                            model: todo, exclude: reactive_connection_id)
  end

  def view_template
    div(**reactive_root(class: 'flex flex-col gap-3')) do
      turbo_stream_from(*Todo.stream_key) # subscribe to cross-tab updates

      ul(id: 'todos', class: 'flex flex-col') do
        if Todo.exists?
          Todo.order(:created_at, :id).each { render TodoItemComponent.new(todo: it) }
        else
          render TodoEmptyComponent.new
        end
      end

      div(class: 'flex gap-2') do
        # Enter in the field adds the todo — the same :add action the button fires
        # on click. event: "keydown.enter" is Stimulus's native keyboard filter,
        # so only Enter dispatches. The field's value rides as the `title` param.
        input(**mix(on(:add, event: 'keydown.enter'),
                    name: 'title', placeholder: 'New todo…', autocomplete: 'off',
                    class: 'input input-bordered flex-1', data: { testid: 'new-todo' }))
        # disable_with: stops a rapid double-click from creating two todos.
        button(**mix(on(:add, disable_with: 'Adding…'),
                     class: 'btn btn-primary', data: { testid: 'add' })) { 'Add' }
        # Client-only tips toggle: show/hide the hint with ZERO round trip — no
        # token, no POST, ever. Pure UX polish the one generic controller applies
        # locally (js.toggle flips the [hidden] flag).
        button(**mix(on_client(:click, js.toggle('#todo-tips')),
                     class: 'btn btn-ghost', data: { testid: 'tips-toggle' })) { 'Tips' }
      end

      p(id: 'todo-tips', hidden: true, class: 'text-xs opacity-60',
        data: { testid: 'todo-tips' }) do
        'Press Enter to add · click the checkbox to toggle · Enter in a row saves the rename.'
      end
    end
  end
end
