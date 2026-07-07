# frozen_string_literal: true

# Record-backed reactive row. Exercises reactive_record (GlobalID identity),
# a param action (rename via change), and a toggle.
#
# Deliberately uses the issue #81 short form as living proof: ONE include
# (Component pulls in Streamable) and NO `def id` (reactive_record :todo
# defaults #id to dom_id(@todo)). The other dummy components keep the legacy
# two-include + explicit-id form so it stays covered too.
class TodoItemComponent < ApplicationComponent
  include Phlex::Reactive::Component

  reactive_record :todo
  action :toggle
  action :rename, params: { title: :string }
  action :archive
  action :rename_strict, params: { title: :string }

  def initialize(todo:)
    @todo = todo
  end

  # No `def id` needed: reactive_record :todo defaults #id to dom_id(@todo).
  # No model_param_name override needed: reactive_record :todo makes the
  # broadcast path build with the same `todo:` keyword the action endpoint uses.

  def toggle
    @todo.update!(done: !@todo.done?)
  end

  def rename(title:)
    @todo.update!(title:) if title.present?
  end

  # reply is the ONE door (issue #182 — the former Response.* class verbs are gone).

  # Remove self from the DOM (render_self false — no doomed re-render).
  def archive
    reply.remove
  end

  # Surface a validation error as a flash while still refreshing the row's token
  # (replace self + flash); on success, plain replace.
  def rename_strict(title:)
    return reply.replace.flash(:error, "blank") if title.blank?

    @todo.update!(title:)
    reply.replace
  end

  def view_template
    li(**mix(reactive_attrs, id:, data: { testid: "todo", done: @todo.done?.to_s })) do
      button(**mix(on(:toggle), data: { testid: "toggle" })) { @todo.done? ? "✓" : "○" }
      input(**mix(on(:rename, event: "change"), name: "title", value: @todo.title))
      # archive returns reply.remove — drops this row in place. (The
      # rename_strict flash-on-blank path would need a second title input that
      # collides with field collection above, so it's covered by the request
      # specs rather than wired into this single-input demo row.)
      button(**mix(on(:archive), data: { testid: "archive" })) { "archive" }
    end
  end
end
