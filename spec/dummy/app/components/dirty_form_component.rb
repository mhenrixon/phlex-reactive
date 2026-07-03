# frozen_string_literal: true

# Dirty-field tracking (issue #103) end-to-end. The browser already holds the
# last server-rendered value with ZERO shipped state: input.defaultValue IS the
# attribute from the last server render, so dirty = current ≠ default.
#
#   * reactive_root(track_dirty: true, warn_unsaved: true) — every input on this
#     root re-scans the owned fields on change (track_dirty mixes
#     input->reactive#trackDirty onto the root's data-action), and warn_unsaved
#     arms a navigate-away guard gated on the LIVE dirty count.
#   * reactive_field(:title, value:, dirty: true) — the field itself also carries
#     the trackDirty descriptor (redundant with the root here, but demonstrates
#     the per-field opt-in).
#   * The "Unsaved" badge is revealed purely by CSS ([data-reactive-dirty]) —
#     no Ruby, no per-field JS. It appears on the first keystroke and clears when
#     the morph reply writes a fresh defaultValue that equals the input's value.
#
# save morphs (reply.morph) so the reply re-renders the field in place with the
# NEW value as its fresh default — the post-morph re-scan then finds it clean and
# the badge clears WITHOUT a full-page reload.
class DirtyFormComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo
  action :save, params: { title: :string }

  def initialize(todo:)
    @todo = todo
  end

  def id = dom_id(@todo, "dirtyform")

  def save(title:)
    @todo.update!(title:) if title.present?
    reply.morph
  end

  def view_template
    div(**reactive_root(track_dirty: true, warn_unsaved: true)) do
      # The field's baseline is its own defaultValue (= @todo.title from this
      # render). dirty: true also wires trackDirty onto the field itself.
      input(**mix(reactive_field(:title, value: @todo.title, dirty: true), data: { testid: "title" }))
      # Revealed purely by CSS while the root is dirty — no Ruby toggles it.
      span(class: "unsaved-badge", data: { testid: "badge" }) { "Unsaved" }
      button(**mix(on(:save), data: { testid: "save" })) { "Save" }
      span(data: { testid: "current" }) { @todo.title }
    end
  end
end
