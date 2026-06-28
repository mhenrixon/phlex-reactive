# frozen_string_literal: true

# A reactive_collection whose container #id EQUALS the append target and whose
# rows are themselves reactive (ReactiveRowComponent carries its own token). This
# is the exact shape from issue #44: rows append directly INTO the container
# element, so the row's embedded data-reactive-token-value lives in the same
# stream string as `target="reactive-rows"` — which fooled carries_token_for? into
# concluding the container's token was already fresh and skipping its refresh,
# making the list add-once-only.
class ReactiveRowsListComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_collection :rows,
    item: ReactiveRowComponent,
    container: "reactive-rows", # rows append INTO this element (== #id)
    size: -> { Todo.count }

  action :add, params: { title: :string }

  # The container's #id IS the append target — the issue #44 trigger.
  def id = "reactive-rows"

  def add(title:)
    todo = Todo.create!(title: title.to_s.strip, done: false)
    reply.append(:rows, todo)
  end

  def view_template
    ul(id:, **reactive_attrs) do
      Todo.order(:created_at, :id).each { render ReactiveRowComponent.new(todo: it) }
    end
  end
end
