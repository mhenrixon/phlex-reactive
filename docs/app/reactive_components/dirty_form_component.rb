# frozen_string_literal: true

# Dirty-field tracking (issue #103) with ZERO shipped state. The browser already
# holds the last server-rendered value: input.defaultValue IS the attribute from
# the last render, so dirty = current ≠ default — no state travels to the client.
#
#   * reactive_dirty warn_unsaved: true — a CLASS-LEVEL declaration (issue #184):
#     every input on the root re-scans on change (the root delegates
#     input->reactive#trackDirty), and warn_unsaved arms a navigate-away guard
#     gated on the LIVE dirty count.
#   * reactive_field(:title, value:) — the field carries the wire name; dirty
#     tracking rides on the class-level declaration above (no per-field kwarg).
#   * The "Unsaved" badge is revealed purely by CSS ([data-reactive-dirty]) — no
#     Ruby, no per-field JS. It appears on the first keystroke and clears when the
#     morph reply writes a fresh defaultValue equal to the input's value.
#
# save morphs so the reply re-renders the field with the NEW value as its fresh
# default; the post-morph re-scan then finds it clean and the badge clears with no
# full-page reload.
class DirtyFormComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo
  reactive_dirty warn_unsaved: true
  action :save, params: { title: :string }

  def initialize(todo:)
    @todo = todo
  end

  def id = dom_id(@todo, 'dirtyform')

  def save(title:)
    @todo.update!(title:) if title.present?
    reply.morph
  end

  def view_template
    # The badge is hidden until the root carries data-reactive-dirty (set live by
    # trackDirty when current ≠ default), then revealed — pure CSS, no Ruby.
    style do
      # Static CSS, no user input — Phlex safe(), not Rails html_safe.
      css = '[data-testid="dirty-badge"]{display:none} ' \
            '[data-reactive-dirty] [data-testid="dirty-badge"]{display:inline-flex}'
      raw(safe(css)) # rubocop:disable Rails/OutputSafety
    end
    div(**reactive_root(class: 'flex items-center gap-2')) do
      # The field's baseline is its own defaultValue (= @todo.title from this
      # render). Dirty tracking is wired by the class-level reactive_dirty above.
      input(**mix(reactive_field(:title, value: @todo.title),
                  class: 'input input-bordered input-sm', data: { testid: 'title' }))
      # Revealed purely by CSS while the root is dirty — no Ruby toggles it.
      span(class: 'badge badge-warning badge-sm', data: { testid: 'dirty-badge' }) { 'Unsaved' }
      button(**mix(on(:save), class: 'btn btn-sm btn-primary', data: { testid: 'save' })) { 'Save' }
      span(class: 'text-sm opacity-60', data: { testid: 'current' }) { @todo.title }
    end
  end
end
