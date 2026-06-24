# frozen_string_literal: true

# Record-backed reactive component that ALSO carries transient mode as signed
# state (issue #6 / docs/examples/inline_edit.md). `record` is re-found via
# GlobalID; `attribute` (which column) and `editing` (the mode) are signed
# state that must survive every action round trip.
class InlineEditComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :record
  reactive_state :attribute, :editing

  action :edit
  action :cancel
  action :save, params: {value: :string}

  def initialize(record:, attribute:, editing: false)
    @record = record
    @attribute = attribute.to_sym
    @editing = editing
  end

  def id = dom_id(@record, "inline_#{@attribute}")

  def edit = @editing = true
  def cancel = @editing = false

  def save(value:)
    @record.update!(@attribute => value)
    @editing = false
  end

  def view_template
    span(id:, **reactive_attrs) do
      if @editing
        # The input only holds the value — the form fields it collects travel
        # with whichever action fires. `on(:save)` lives on the Save button, not
        # the input, so focusing the field doesn't dispatch save and collapse
        # edit mode (matches docs/examples/inline_edit.md).
        input(name: "value", value: current_value, data: {testid: "field"})
        button(**mix(on(:save), data: {testid: "save"})) { "Save" }
        button(**mix(on(:cancel), data: {testid: "cancel"})) { "Cancel" }
      else
        span(**mix(on(:edit), data: {testid: "display"})) { current_value.presence || "—" }
      end
    end
  end

  private

  def current_value = @record.public_send(@attribute).to_s
end
