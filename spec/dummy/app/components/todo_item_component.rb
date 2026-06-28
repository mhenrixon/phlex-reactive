# frozen_string_literal: true

# Record-backed reactive row. Exercises reactive_record (GlobalID identity),
# a param action (rename via change), and a toggle.
class TodoItemComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo
  action :toggle
  action :rename, params: { title: :string }
  action :archive
  action :rename_strict, params: { title: :string }

  def initialize(todo:)
    @todo = todo
  end

  # Streamable#dom_id is render-context-free
  def id = dom_id(@todo)
  # No model_param_name override needed: reactive_record :todo makes the
  # broadcast path build with the same `todo:` keyword the action endpoint uses.

  def toggle
    @todo.update!(done: !@todo.done?)
  end

  def rename(title:)
    @todo.update!(title:) if title.present?
  end

  # This component deliberately keeps the fully-qualified
  # Phlex::Reactive::Response.* form (the others use the preferred reply.*) so the
  # back-compat path stays covered by the live request/system suites: reply.* is
  # sugar over Response.*, and Response.* must keep working verbatim.

  # Response: remove self from the DOM (render_self false — no doomed re-render).
  def archive
    Phlex::Reactive::Response.remove(self)
  end

  # Response: surface a validation error as a flash while still refreshing the
  # row's token (replace self + flash); on success, plain replace.
  def rename_strict(title:)
    return Phlex::Reactive::Response.replace(self).flash(:error, "blank") if title.blank?

    @todo.update!(title:)
    Phlex::Reactive::Response.replace(self)
  end

  def view_template
    li(**mix(reactive_attrs, id:, data: { testid: "todo", done: @todo.done?.to_s })) do
      button(**mix(on(:toggle), data: { testid: "toggle" })) { @todo.done? ? "✓" : "○" }
      input(**mix(on(:rename, event: "change"), name: "title", value: @todo.title))
      # archive returns Response.remove(self) — drops this row in place. (The
      # rename_strict flash-on-blank path would need a second title input that
      # collides with field collection above, so it's covered by the request
      # specs rather than wired into this single-input demo row.)
      button(**mix(on(:archive), data: { testid: "archive" })) { "archive" }
    end
  end
end
