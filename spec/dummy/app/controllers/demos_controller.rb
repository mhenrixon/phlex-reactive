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

  def debounce
    render_component DebounceComponent.new
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
