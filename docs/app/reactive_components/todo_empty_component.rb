# frozen_string_literal: true

# The empty-state shown when the todo list has no rows. The reactive_collection
# helper removes it by its stable #id when the first row is added, and appends it
# back when the last row is archived. A static view (Streamable only) — it has no
# actions or state, it's just a broadcastable/self-targeting element.
class TodoEmptyComponent < Phlex::HTML
  include Phlex::Reactive::Streamable

  def id = 'todos-empty'

  def view_template
    li(id:, class: 'py-3 text-sm opacity-60', data: { testid: 'todos-empty' }) do
      'Nothing here yet — add your first todo above.'
    end
  end
end
