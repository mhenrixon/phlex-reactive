# frozen_string_literal: true

# Issue #95: a component whose ENTIRE interactivity is client-side on_client ops —
# tabs that switch panels, a menu that closes on any outside click, and an
# accessible drawer with a transition + focus op — with ZERO server round trips.
# It deliberately declares NO actions: there is no token-bearing trigger anywhere,
# and the system spec's fetch spy proves nothing is ever posted. The root carries
# the window-bound outside-close trigger permanently (a client op costs nothing per
# stray page click, unlike a server action).
class ClientTabsComponent < Phlex::HTML
  include Phlex::Reactive::Component

  def id = 'client-tabs'

  def view_template
    # The fade transition classes for the drawer's js.toggle(transition:). Scoped
    # inline so the demo is self-contained (no global CSS needed).
    style do
      css = '.ct-fade{transition:opacity .2s ease} .ct-fade-from{opacity:0} .ct-fade-to{opacity:1} ' \
            '#ct-panel-1,#ct-panel-2{padding:.75rem 0} .ct-tab.active{font-weight:600;color:var(--color-primary)}'
      raw(safe(css)) # rubocop:disable Rails/OutputSafety
    end
    div(**mix(reactive_root, on_client(:click, js.hide('#ct-menu'), outside: true),
              class: 'flex flex-col gap-4')) do
      tabs
      panels
      menu
      drawer
    end
  end

  private

  def tabs
    div(role: 'tablist', class: 'flex gap-2 border-b border-base-300') do
      tab_button(1, 'Overview', active: true)
      tab_button(2, 'Details', active: false)
    end
  end

  # One op chain per tab: hide every panel, show the picked one, restyle the tab
  # buttons — the canonical "I had to write a Stimulus controller" case, now one
  # line of declared client ops.
  def tab_button(index, label, active:)
    ops = js.hide('.ct-panel').show("#ct-panel-#{index}")
            .remove_class('.ct-tab', 'active').add_class("#ct-tab-#{index}", 'active')

    button(**mix(on_client(:click, ops),
                 id: "ct-tab-#{index}", class: ['ct-tab px-3 py-1', ('active' if active)].compact,
                 data: { testid: "tab-#{index}" })) { label }
  end

  def panels
    div(id: 'ct-panel-1', class: 'ct-panel', data: { testid: 'panel-1' }) do
      'The Overview panel — shown by default.'
    end
    div(id: 'ct-panel-2', class: 'ct-panel', hidden: true, data: { testid: 'panel-2' }) do
      'The Details panel — revealed by a pure client op.'
    end
  end

  def menu
    div(class: 'flex flex-col gap-2') do
      button(**mix(on_client(:click, js.show('#ct-menu')),
                   class: 'btn btn-sm w-fit', data: { testid: 'menu-open' })) { 'Open menu' }
      div(id: 'ct-menu', hidden: true, class: 'rounded-box border border-base-300 p-3',
          data: { testid: 'menu' }) { 'Menu content — click anywhere outside to close.' }
    end
  end

  # Issue #96: a drawer opened with a TRANSITION (animated fade), an aria-expanded
  # attr op on the trigger, and a FOCUS op landing on the first focusable control
  # inside the drawer — the exact accessible-disclosure pattern, one op chain.
  def drawer
    open = js
           .toggle('#ct-drawer', transition: %w[ct-fade ct-fade-from ct-fade-to])
           .set_attr(:root, 'aria-expanded', 'true')
           .focus_first('#ct-drawer')

    div(class: 'flex flex-col gap-2') do
      button(**mix(on_client(:click, open),
                   id: 'ct-drawer-trigger', class: 'btn btn-sm w-fit',
                   data: { testid: 'drawer-open' })) { 'Open drawer' }
      div(id: 'ct-drawer', hidden: true, class: 'rounded-box border border-base-300 p-3 flex gap-2',
          data: { testid: 'drawer' }) do
        button(class: 'btn btn-xs', data: { testid: 'drawer-first' }) { 'First action' }
        button(class: 'btn btn-xs', data: { testid: 'drawer-second' }) { 'Second action' }
      end
    end
  end
end
