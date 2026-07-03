# frozen_string_literal: true

# Renders the example pages exercised by the system specs. Uses the ERB
# application layout (which loads Turbo + Stimulus + the reactive controller)
# and renders the Phlex component as its body via phlex-rails.
class DemosController < ActionController::Base
  layout "application"

  def counter
    render_component CounterComponent.new(count: 0)
  end

  # User-visible failure surface (issue #100): a boom (undeclared → 403 with an
  # error_flash), a success that clears data-reactive-error, and a self-dismissing
  # flash. The page carries a server-rendered <template data-reactive-error-flash>
  # so the offline fallback has something to clone (not exercised without a real
  # network failure, but proves the opt-in renders).
  def failure_surface
    component = render_to_string(FailureSurfaceComponent.new(count: 0), layout: false)
    template = <<~HTML
      <template data-reactive-error-flash>
        <div class="reactive-flash reactive-flash--error" data-testid="offline-flash">You are offline</div>
      </template>
    HTML
    render html: component + template.html_safe, layout: true
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

  # Pure client-side interactivity (issue #95, extended in #96): on_client + js
  # ops. The page carries an outside area so the spec can prove the outside-close
  # op, a fetch spy proves NOTHING is ever posted, and a real @keyframes fade
  # (ct-fade-to) drives the #96 transition op so animationend actually fires.
  def client_tabs
    component = render_to_string(ClientTabsComponent.new, layout: false)
    extras = <<~HTML
      <style>
        @keyframes ct-fade-in { from { opacity: 0 } to { opacity: 1 } }
        .ct-fade-to { animation: ct-fade-in 40ms ease-out }
      </style>
      <div data-testid="outside-area" style="padding: 4rem">outside the tabs</div>
    HTML
    render html: component + extras.html_safe, layout: true
  end

  def confirm
    render_component ConfirmComponent.new
  end

  # Optimistic visual hints (issue #98): a checkbox that flips natively before
  # the (deliberately slow) morph, a failing action whose hint reverts, and a
  # hide-then-remove delete. A fresh, unfinished Todo each visit.
  def optimistic
    todo = Todo.create!(title: "optimistic", done: false)
    component = render_to_string(OptimisticRowComponent.new(todo:), layout: false)
    render html: %(<ul>#{component}</ul>).html_safe, layout: true
  end

  # Declarative loading states (issue #99): a disable_with button that disables +
  # swaps its text while a slow save runs, so a rapid double-click enqueues only
  # ONE POST (the disabled button swallows the second), plus a busy_on spinner.
  def loading_button
    render_component LoadingButtonComponent.new(count: 0)
  end

  def morph_grid
    render_component MorphGridComponent.new(account: Account.find(params[:id]))
  end

  # Issue #97: post-save focus lands on the freshly morphed field via
  # reply.morph.js(js.focus(...)) — the reactive:js op stream rides AFTER the
  # morph so focus targets the morphed node.
  def js_focus
    render_component JsFocusComponent.new(account: Account.find(params[:id]))
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
