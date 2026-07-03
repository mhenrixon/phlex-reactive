# frozen_string_literal: true

# Record-backed reactive row. Identity is the Todo's GlobalID (reactive_record),
# so the signed token re-finds the record server-side — never trusts client state.
#
# Demonstrates the full per-row toolkit, all without a Stimulus controller:
#   * an OPTIMISTIC toggle (checked: :keep) that flips the checkbox the instant
#     you click, before the round trip; the morph reconciles from server truth, a
#     failure snaps it back;
#   * an inline rename that saves on Enter and morphs in place so the field keeps
#     focus + caret (reply.morph over reply.replace);
#   * an OPTIMISTIC archive (hide: true) that hides the row NOW; reply.remove then
#     drops it, so it never flashes back;
#   * a broadcast on every change so the OTHER tabs see the same row update
#     (exclude: reactive_connection_id suppresses the actor's own echo).
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

  # Toggle done, then broadcast the reconciled row to the other tabs. A replace is
  # keyed by dom id, so idiomorph dedupes it for the actor even without exclude:;
  # passing exclude: keeps every action on one consistent pattern.
  def toggle
    @todo.update!(done: !@todo.done?)
    broadcast
  end

  # Morph in place so the rename input keeps focus + caret after an Enter save,
  # then broadcast the new title to the other tabs.
  def rename(title:)
    @todo.update!(title:) if title.present?
    broadcast
    reply.morph
  end

  # Destroy the record, drop this tab's row in place (reply.remove — no doomed
  # self re-render), and broadcast the removal to the other tabs. Remove is
  # idempotent, so exclude: only spares the actor a redundant echo.
  def archive
    @todo.destroy!
    TodoItemComponent.broadcast_remove_to(*Todo.stream_key, model: @todo, exclude: reactive_connection_id)
    reply.remove
  end

  def view_template
    li(**mix(reactive_root, class: 'flex items-center gap-2 py-1',
                            data: { testid: 'todo', done: @todo.done?.to_s })) do
      # The optimistic checkbox: checked: :keep lets the native flip happen NOW
      # (it skips the unconditional preventDefault), so the box ticks in the same
      # gesture; the morph then overwrites with server truth, a failure reverts it.
      input(type: 'checkbox', checked: @todo.done?,
            **mix(on(:toggle, event: 'change', optimistic: { checked: :keep }),
                  class: 'checkbox checkbox-sm', data: { testid: 'toggle' }))
      # Enter saves the rename (event: "keydown.enter" is Stimulus's native
      # keyboard filter, so ONLY Enter fires it). The Todo's title travels as the
      # `title` param (a named control of this row).
      input(**mix(on(:rename, event: 'keydown.enter'),
                  name: 'title', value: @todo.title,
                  data: { testid: 'todo-title' },
                  class: ['input input-sm flex-1', ('line-through opacity-60' if @todo.done?)]))
      # Instant delete: hide the row NOW (optimistic), remove it on the reply.
      # disable_with: guards against a rapid double-click firing archive twice.
      button(**mix(on(:archive, disable_with: '…', optimistic: { hide: true, to: :root }),
                   class: 'btn btn-xs btn-ghost', data: { testid: 'archive' })) { 'archive' }
    end
  end

  private

  # Re-render this row into every OTHER subscribed tab — exclude the actor, whose
  # own reply.morph / self-replace already updated them.
  def broadcast
    TodoItemComponent.broadcast_replace_to(*Todo.stream_key, model: @todo, exclude: reactive_connection_id)
  end
end
