# frozen_string_literal: true

# Issue #241: reactive_persist over RICH editors. The same token-less
# ClientBindings draft as PersistFormComponent, but the owned controls are
# the real editors: a `lexxy-editor` (name on the element, initial HTML via
# its `value` attribute), a `trix-editor` in the Rails rich_text_area shape
# (a hidden input carries the name; the editor points at it via `input=`),
# and a bare named `[contenteditable]`. Each is restored through its OWN
# value surface — the editor's `value` setter, the contenteditable's
# textContent — never innerHTML. A second Lexxy editor opts out with
# reactive_persist_skip ON THE EDITOR ELEMENT.
#
# The editors are imported by this component (importmap pins `trix` and
# `lexxy`), so only this page pays for them. `late:` defers both imports
# past the reactive controller's connect to exercise the customElements
# whenDefined deferral in a real browser (Trix ALWAYS defines its elements
# in a setTimeout after load, so the eager page exercises it for Trix too).
class PersistEditorsFormComponent < ApplicationComponent
  include Phlex::Reactive::ClientBindings

  register_element :lexxy_editor
  register_element :trix_editor

  reactive_scope :draft

  def initialize(body: nil, notes: nil, late: false)
    @body = body
    @notes = notes
    @late = late
  end

  def view_template
    form(action: "/persist_editors", method: "post", data: { testid: "form" }) do
      div(**mix(reactive_root(id: "persist-editors"),
        reactive_persist(key: "dummy-editors", ttl: 1.hour, debounce: 100))) do
        input(**reactive_field(:title, type: "text", data: { testid: "title" }))
        # Lexxy: `value` is the server-rendered HTML (?body=) the draft must not overwrite.
        lexxy_editor(name: "draft[body]", value: @body, data: { testid: "body" })
        # Trix (Rails shape): the hidden input owns the name and the server value (?notes=).
        input(type: "hidden", name: "draft[notes]", id: "draft_notes_trix_input", value: @notes,
          data: { testid: "notes-input" })
        trix_editor(input: "draft_notes_trix_input", data: { testid: "notes" })
        # A bare contenteditable: text in, text out.
        div(contenteditable: "true", name: "draft[summary]", data: { testid: "summary" })
        # Never persisted: the skip marker sits on the editor element itself.
        lexxy_editor(name: "draft[private]", **mix(reactive_persist_skip, data: { testid: "private" }))

        button(**mix(on_client(:click, js.persist_clear), data: { testid: "discard" })) { "Discard" }
        button(type: "submit", data: { testid: "submit" }) { "Save" }
      end
    end
    script(type: "module") { raw(safe(editor_imports)) }
  end

  private

  def editor_imports
    return "import \"trix\"\nimport \"lexxy\"\n" unless @late

    "setTimeout(() => { import(\"trix\"); import(\"lexxy\") }, 300)\n"
  end
end
