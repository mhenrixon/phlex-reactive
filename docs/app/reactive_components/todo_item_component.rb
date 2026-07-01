# frozen_string_literal: true

# Record-backed reactive row. Identity is the Todo's GlobalID (reactive_record),
# so the signed token re-finds the record server-side — never trusts client state.
# Demonstrates a toggle, an inline rename that saves on Enter (key: "Enter") AND
# on blur (change), and an archive that removes the row from the DOM via
# reply.remove.
class TodoItemComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo
  action :toggle
  action :rename, params: { title: :string }
  action :archive

  def initialize(todo:)
    @todo = todo
  end

  # Streamable#dom_id is render-context-free.
  def id = dom_id(@todo)

  def toggle
    @todo.update!(done: !@todo.done?)
  end

  # Morph in place so the rename input keeps focus + caret after an Enter save.
  def rename(title:)
    @todo.update!(title:) if title.present?
    reply.morph
  end

  # Reply: drop this row from the DOM in place (no doomed self re-render).
  def archive
    @todo.destroy!
    reply.remove
  end

  def view_template
    li(**mix(reactive_root, class: 'flex items-center gap-2 py-1',
                            data: { testid: 'todo', done: @todo.done?.to_s })) do
      button(**mix(on(:toggle), class: 'btn btn-xs btn-circle',
                                data: { testid: 'toggle' })) { @todo.done? ? '✓' : '○' }
      # Enter saves the rename (key: "Enter" → Stimulus keydown.enter, so ONLY
      # Enter fires it — not every keystroke). The Todo's title travels as the
      # `title` param because the input is a named control of this reactive row.
      input(**mix(on(:rename, key: 'Enter'),
                  name: 'title', value: @todo.title,
                  data: { testid: 'todo-title' },
                  class: ['input input-sm flex-1', ('line-through opacity-60' if @todo.done?)]))
      button(**mix(on(:archive), class: 'btn btn-xs btn-ghost',
                                 data: { testid: 'archive' })) { 'archive' }
    end
  end
end
