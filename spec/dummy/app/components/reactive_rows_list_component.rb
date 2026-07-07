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
    reply.append(todo, to: :rows)
  end

  def view_template
    # The <ul> IS the reactive root (its #id == the append target "reactive-rows").
    # The add trigger lives INSIDE it so on(:add) binds to THIS list controller —
    # each click consumes the container's signed token, which the previous add's
    # trailing reactive:token stream must have rolled forward (issue #46). New rows
    # prepend ABOVE the trigger <li> so the control row stays at the bottom.
    ul(id:, **reactive_attrs) do
      Todo.order(:created_at, :id).each { render ReactiveRowComponent.new(todo: it) }

      li(data: { testid: "add-controls" }) do
        input(name: "title", placeholder: "New row…", autocomplete: "off", data: { testid: "new-row" })
        button(**mix(on(:add), data: { testid: "add-row" })) { "Add row" }
      end
    end
  end
end
