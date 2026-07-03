# frozen_string_literal: true

# Record-backed reactive component that ALSO carries transient mode as signed
# state (issue #6). `record` is re-found via GlobalID; `attribute` (which column)
# and `editing` (the show ↔ edit mode) are signed state that must survive every
# action round trip — the classic "click to edit, Enter to save, Escape to
# cancel" widget that would otherwise be a Stimulus controller plus three routes.
class InlineEditComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :record
  reactive_state :attribute, :editing

  action :edit
  action :cancel
  action :save, params: { value: :string }

  def initialize(record:, attribute: :title, editing: false)
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
    span(**reactive_root(class: 'inline-flex items-center gap-2')) do
      if @editing
        # The input only holds the value — the form fields it collects travel with
        # whichever action fires. `on(:save)` lives on the Save button, not the
        # input, so focusing the field doesn't dispatch save and collapse edit mode.
        # Escape in the field cancels — event: "keydown.esc" is Stimulus's native
        # keyboard filter, so ONLY Escape fires it (Enter is free to save elsewhere).
        input(**mix(on(:cancel, event: 'keydown.esc'),
                    name: 'value', value: current_value,
                    class: 'input input-bordered input-sm', data: { testid: 'field' }))
        button(**mix(on(:save), class: 'btn btn-sm btn-primary', data: { testid: 'save' })) { 'Save' }
        button(**mix(on(:cancel), class: 'btn btn-sm btn-ghost', data: { testid: 'cancel' })) { 'Cancel' }
      else
        span(**mix(on(:edit),
                   class: 'cursor-pointer border-b border-dashed border-base-content/40',
                   data: { testid: 'display' })) { current_value.presence || '—' }
        span(class: 'text-xs opacity-50') { '(click to edit)' }
      end
    end
  end

  private

  def current_value = @record.public_send(@attribute).to_s
end
