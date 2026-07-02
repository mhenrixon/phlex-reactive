# frozen_string_literal: true

# Exercises the outside: event modifier (issue #80): the canonical
# close-a-dropdown-on-outside-click. While the menu is OPEN the root binds
# on(:close_menu, outside: true) — a window-bound click that fires only for
# targets OUTSIDE this root. A click inside the root is a complete client-side
# no-op, and the window binding never preventDefaults, so links elsewhere on
# the page keep navigating. `closes` counts how many times close_menu actually
# ran, so the spec can prove an inside click contributed nothing.
class DropdownMenuComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :open, :closes

  action :toggle_menu
  action :close_menu

  def initialize(open: false, closes: 0)
    @open = open
    @closes = closes
  end

  def id = "dropdown"

  def toggle_menu
    @open = !@open
  end

  def close_menu
    @open = false
    @closes += 1
  end

  def view_template
    div(**root_attrs) do
      button(**mix(on(:toggle_menu), data: { testid: "menu-button" })) { "Menu" }
      span(data: { testid: "closes" }) { @closes.to_s }
      if @open
        ul(data: { testid: "menu" }) do
          li(data: { testid: "menu-item" }) { "Item one" }
        end
      end
    end
  end

  private

  # Bind the outside-click close ONLY while open — a closed menu shouldn't
  # round-trip on every stray page click.
  def root_attrs
    return reactive_root unless @open

    mix(reactive_root, on(:close_menu, outside: true))
  end
end
