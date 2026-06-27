# frozen_string_literal: true

# Exercises the reactive_input/reactive_select param-binding helpers (issue #23).
# The edit-mode controls bind to the :save action's `value:`/`status:` params via
# reactive_input/reactive_select — no hand-written `name: "value"` magic string.
class ReactiveInputComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :record
  reactive_state :attribute

  action :save, params: {value: :string, status: :string}

  STATUSES = %w[open closed].freeze

  def initialize(record:, attribute: :title)
    @record = record
    @attribute = attribute.to_sym
  end

  def id = dom_id(@record, "reactive_input")

  def save(value: nil, status: nil)
    @record.update!(@attribute => value) if value
    @record.update!(@attribute => status) if status
  end

  def view_template
    div(id:, **reactive_attrs) do
      # name="value" emitted by the helper, not hand-written.
      reactive_input(:value, value: @record.public_send(@attribute).to_s, data: {testid: "field"})

      reactive_select(:status, data: {testid: "status"}) do
        STATUSES.each { |s| option(value: s) { s } }
      end

      button(**mix(on(:save), data: {testid: "save"})) { "Save" }
    end
  end
end
