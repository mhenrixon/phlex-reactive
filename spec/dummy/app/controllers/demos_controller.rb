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

  def combobox
    # Seed the query so options render on load — the system spec drives keyboard
    # nav without hammering the debounced search (which stresses Falcon's fibers).
    render_component ComboboxComponent.new(query: params[:q].to_s)
  end

  # A NEW (unsaved) order: the split recomputes in-browser via reactive_compute,
  # no round trip. total=500 seeds the three-way split.
  def new_order
    render_component OrderComponent.new(order: Order.new(total: 500))
  end

  # A PERSISTED order: editing allowance fires the reactive rebalance action and
  # the server reconciles cash through the same PaymentSplit twin.
  def order
    render_component OrderComponent.new(order: Order.find(params[:id]))
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

  # The outside-click dropdown (issue #80). The page carries content OUTSIDE the
  # reactive root — a plain area to click and a real link — so the system spec
  # can prove the outside close fires AND that the window-bound trigger never
  # preventDefaults native navigation elsewhere on the page.
  def dropdown
    component = render_to_string(DropdownMenuComponent.new, layout: false)
    outside = <<~HTML
      <div data-testid="outside-area" style="padding: 4rem">outside the menu</div>
      <a href="/nav_probe" data-testid="outside-link">elsewhere</a>
    HTML
    # render_to_string returns a SafeBuffer whose #to_s returns SELF, so a
    # `component.to_s + outside` concat ESCAPES the raw fixture into visible
    # text. Appending an html_safe right-hand side concatenates verbatim.
    render html: component + outside.html_safe, layout: true
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
