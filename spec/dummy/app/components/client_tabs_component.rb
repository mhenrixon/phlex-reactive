# frozen_string_literal: true

# Issue #95: a component whose ENTIRE interactivity is client-side on_client
# ops — tabs that switch panels and a menu that closes on any outside click —
# with ZERO server round trips. It deliberately declares NO actions: there is
# no token-bearing trigger anywhere, and the system spec's fetch spy proves
# nothing is ever posted. The root carries the window-bound outside-close
# trigger permanently (a client op costs nothing per stray page click, unlike
# a server action).
class ClientTabsComponent < ApplicationComponent
  include Phlex::Reactive::Component

  def id = "client-tabs"

  def view_template
    div(**mix(reactive_root, on_client(:click, js.hide("#ct-menu"), outside: true))) do
      tabs
      panels
      menu
      drawer
    end
  end

  private

  def tabs
    div do
      tab_button(1, "One", active: true)
      tab_button(2, "Two", active: false)
    end
  end

  # One op chain per tab: hide every panel, show the picked one, restyle the
  # tab buttons — the canonical "I had to write a Stimulus controller" case,
  # now one line of declared ops.
  def tab_button(index, label, active:)
    ops = js.hide(".ct-panel").show("#ct-panel-#{index}")
      .remove_class(".ct-tab", "active").add_class("#ct-tab-#{index}", "active")

    button(**mix(on_client(:click, ops),
      id: "ct-tab-#{index}", class: ["ct-tab", active ? "active" : nil].compact,
      data: { testid: "tab-#{index}" })) { label }
  end

  def panels
    div(id: "ct-panel-1", class: "ct-panel", data: { testid: "panel-1" }) { "First panel" }
    div(id: "ct-panel-2", class: "ct-panel", hidden: true, data: { testid: "panel-2" }) { "Second panel" }
  end

  def menu
    button(**mix(on_client(:click, js.show("#ct-menu")), data: { testid: "menu-open" })) { "Menu" }
    div(id: "ct-menu", hidden: true, data: { testid: "menu" }) { span { "menu content" } }
  end

  # Issue #96: a drawer opened with a TRANSITION (animated fade), an
  # aria-expanded attr op on the trigger, and a FOCUS op landing on the first
  # focusable control inside the drawer — the exact "I had to write Stimulus"
  # accessible-disclosure pattern, now one op chain.
  def drawer
    open = js
      .toggle("#ct-drawer", transition: %w[ct-fade ct-fade-from ct-fade-to])
      .set_attr(:root, "aria-expanded", "true")
      .focus_first("#ct-drawer")

    button(**mix(on_client(:click, open),
      id: "ct-drawer-trigger", data: { testid: "drawer-open" })) { "Open drawer" }
    div(id: "ct-drawer", hidden: true, data: { testid: "drawer" }) do
      button(data: { testid: "drawer-first" }) { "First action" }
      button(data: { testid: "drawer-second" }) { "Second action" }
    end
  end
end
