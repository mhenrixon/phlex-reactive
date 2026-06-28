# frozen_string_literal: true

# Outer reactive editor that CONTAINS nested reactive rows (issue #15). Its own
# `notes` input is a sibling of the nested rows' `quantity` inputs in the DOM.
# When `save` fires on the editor, field collection must stop at the nested
# reactive roots: the editor must receive ONLY `notes`, never the rows' bare
# `quantity`. To prove exactly which params arrived, `save` only accepts the
# declared scalar `notes` and reflects whether it leaked by recording the keys
# it actually got into a visible "saved" marker.
class NestedEditorComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :notes, :saved
  action :save, params: { notes: :string }

  def initialize(notes: "", saved: nil)
    @notes = notes
    @saved = saved
  end

  def id = "editor"

  def save(notes:)
    @notes = notes
    @saved = "saved:#{notes}"
  end

  def view_template
    div(id:, **reactive_attrs) do
      input(name: "notes", value: @notes, data: { testid: "editor-notes" })
      button(**mix(on(:save), data: { testid: "editor-save" })) { "Save editor" }
      span(data: { testid: "editor-saved" }) { @saved.to_s }

      # Two nested reactive roots, each owning a bare `quantity` input. Pre-fix,
      # the editor's save swept BOTH rows' quantity (last one wins) into its own
      # params and raised ArgumentError (unknown keyword :quantity) or silently
      # collided. Post-fix they're invisible to the editor's save.
      render NestedRowComponent.new(label: "a", quantity: "11")
      render NestedRowComponent.new(label: "b", quantity: "22")
    end
  end
end
