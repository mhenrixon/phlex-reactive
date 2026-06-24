# frozen_string_literal: true

# Reproduces issue #8: a reactive `save` whose value lives in a custom editor
# element (a `[contenteditable]` here, standing in for lexxy-editor/trix-editor),
# NOT an input/select/textarea. Before the fix, #collectFields skipped it and
# `save` received an empty `title`, silently wiping the record.
class RichEditorComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo
  action :save, params: {title: :string}

  def initialize(todo:)
    @todo = todo
  end

  def id = dom_id(@todo, "rich")

  def save(title:)
    @todo.update!(title:) if title.present?
  end

  def view_template
    div(id:, **reactive_attrs) do
      form(**on(:save, event: "submit")) do
        # A named custom editor (contenteditable) — NOT input/select/textarea.
        # Its text content is the value to collect.
        div(
          contenteditable: "true",
          name: "title",
          data: {testid: "editor"}
        ) { @todo.title }
        button(type: "submit", data: {testid: "save"}) { "Save" }
      end
      span(data: {testid: "current"}) { @todo.title }
    end
  end
end
