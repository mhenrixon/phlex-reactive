# frozen_string_literal: true

# The reactive_text + typed-compute example (issue #104) — a live title preview
# and character counter that update IN-BROWSER as you type, with NO round trip,
# then a save reconciles through the server.
#
# Two things mirror the `title` field client-side:
#
#   * The preview heading is an IDENTITY MIRROR — reactive_text(:title) with no
#     reducer output. The declared input's raw string is synced to its text node
#     on every `input`, so the heading tracks the field with zero reducer wiring.
#   * The character counter is a reducer OUTPUT written to a text node — the
#     "preview" reducer (inputs typed { title: :string }) returns
#     { char_count: `${title.length}/80` }, which has no matching form field, so
#     it lands on the [data-reactive-text="char_count"] node via textContent.
#
# A save fires the reactive `save` action; the server persists the title and
# re-renders, SEEDING the same derived heading + counter so the morph repaints
# them from the authoritative value (the reconcile contract reactive_compute
# documents — the server render must seed what the reducer would).
class PostPreviewComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo

  # Typed inputs (hash form): `title` is read RAW (a :string), never coerced
  # through Number. The lone output — char_count — has no form field, so it
  # resolves to the [data-reactive-text="char_count"] node.
  reactive_compute :preview,
    inputs: { title: :string },
    outputs: %i[char_count]

  action :save, params: { title: :string }

  def initialize(todo:)
    @todo = todo
  end

  def id = dom_id(@todo)

  # Persisted path: save the title, then re-render self. The re-render seeds the
  # SAME derived preview + counter the JS reducer would, so the morph reconciles.
  def save(title:)
    @todo.update!(title:)
    reply.replace
  end

  def view_template
    div(**mix(reactive_root, reactive_compute_attrs(:preview))) do
      # The live preview heading — an identity mirror of `title`. Seed it with the
      # server's current value so the first paint (and any morph) is correct.
      h2(data: { testid: "preview" }) { reactive_text(:title, @todo.title) }

      # The character counter — a reducer output written to this text node. Seed
      # it server-side too (same contract) so a morph doesn't repaint stale text.
      small(data: { testid: "counter" }) { reactive_text(:char_count, char_count(@todo.title)) }

      # A SERVER-ONLY echo of the PERSISTED title (a plain text node, NOT a
      # reactive_text mirror) — the client never touches it, so the system spec
      # uses it as the barrier that the save round trip actually reconciled.
      span(data: { testid: "saved" }) { @todo.title }

      # The title field drives BOTH: the client recompute/mirror on `input` (no
      # round trip) AND, on the save button, the reactive save action. mix so the
      # recompute action deep-merges with reactive_field's data: (Never-Do #8).
      input(**mix(
        reactive_field(:title, value: @todo.title, type: "text", data: { testid: "title" }),
        { data: { action: "input->reactive#recompute" } }
      ))
      # mix so the extra data: (testid) deep-merges with on()'s data-action /
      # -params instead of clobbering them (Never-Do #8).
      button(**mix(on(:save), data: { testid: "save" })) { "Save" }
    end
  end

  private

  # The server twin of the JS reducer's counter — seeds the same derived string
  # on render so the morph reconciles from the authoritative value.
  def char_count(title) = "#{title.to_s.length}/80"
end
