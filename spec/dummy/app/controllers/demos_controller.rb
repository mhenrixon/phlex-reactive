# frozen_string_literal: true

# Renders the example pages exercised by the system specs. Uses the ERB
# application layout (which loads Turbo + Stimulus + the reactive controller)
# and renders the Phlex component as its body via phlex-rails.
class DemosController < ActionController::Base
  layout "application"

  def counter
    render_component CounterComponent.new(count: 0)
  end

  def todos
    render_component TodoListComponent.new
  end

  def notifications
    render_component NotificationsListComponent.new
  end

  def reactive_rows
    render_component ReactiveRowsListComponent.new
  end

  def chat
    room = params[:room].presence || "lobby"
    render_component ChatRoomComponent.new(room:, messages: ChatMessage.for_room(room).last(50))
  end

  def rich_editor
    render_component RichEditorComponent.new(todo: Todo.find(params[:id]))
  end

  def form_submit
    render_component FormSubmitComponent.new(todo: Todo.find(params[:id]))
  end

  def nested_editor
    render_component NestedEditorComponent.new
  end

  def nested_params
    render_component NestedParamsComponent.new
  end

  def debounce
    render_component DebounceComponent.new
  end

  def confirm
    render_component ConfirmComponent.new
  end

  def morph_grid
    render_component MorphGridComponent.new(account: Account.find(params[:id]))
  end

  def partial_grid
    render_component PartialGridComponent.new(line_item: LineItem.find(params[:id]))
  end

  def document_upload
    render_component DocumentUploadComponent.new(document: Document.find(params[:id]))
  end

  # The page a non-intercepted form submit would navigate to (issue #11).
  def nav_probe
    render html: "<div data-testid='nav-probe'>NAVIGATED</div>".html_safe, layout: true
  end

  private

  # Render a Phlex component as the layout's body. `render component, layout:`
  # is phlex-rails; we capture it into the ERB layout via a content block.
  def render_component(component)
    html = render_to_string(component, layout: false)
    render html: html.html_safe, layout: true
  end
end
