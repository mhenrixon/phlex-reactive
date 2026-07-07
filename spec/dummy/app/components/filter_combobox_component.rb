# frozen_string_literal: true

# A preload-and-filter combobox exercising client-side option filtering
# (issue #163) — the other half of #72's keyboard nav.
#
# The whole (small, static) catalog renders at first paint, grouped by
# category. The root declares `reactive_filter`, so typing in the search input
# narrows the options ENTIRELY client-side — zero round trips: each option
# carries a `data-reactive-filter-text` haystack (name + synonyms), a group
# collapses when every contained option filters out, and the empty node
# reveals at 0 matches. The input carries `reactive_listnav` (the STANDALONE
# keyboard wiring — no action, so no POST per keystroke) and each option stays
# its own signed on(:select) trigger: only FILTERING is local, selection still
# round-trips.
class FilterComboboxComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  # name => haystack (what typing matches against — synonyms included, so
  # "veg" finds Carrot even though the label never says "vegetable").
  CATALOG = {
    "Fruits" => {
      "Apple" => "apple fruit sweet",
      "Banana" => "banana fruit yellow",
      "Cherry" => "cherry fruit red"
    },
    "Vegetables" => {
      "Carrot" => "carrot vegetable orange",
      "Kale" => "kale vegetable leafy green"
    }
  }.freeze

  reactive_state :selected
  action :select, params: { name: :string }

  def initialize(selected: nil)
    @selected = selected
  end

  def id = "filter_combobox"

  def select(name:)
    @selected = name if CATALOG.any? { |_, entries| entries.key?(name) }
    reply.morph
  end

  def view_template
    div(**mix(
      reactive_root(data: { testid: "filter-combobox" }),
      # Issue #186: name the driving field (:q → [name="q"]); option defaults to the
      # [role=option] convention; group/empty are opt-in.
      reactive_filter(:q, group: "[data-filter-group]", empty: "#filter-combobox-empty")
    )) do
      search_input
      CATALOG.each { |category, entries| group(category, entries) }
      div(id: "filter-combobox-empty", hidden: true, data: { testid: "filter-empty" }) { "No matches" }
      selection if @selected.present?
    end
  end

  private

  # No on(...) here — filtering never POSTs. reactive_listnav wires
  # Arrow/Enter/Escape standalone (Enter clicks the highlighted option's own
  # reactive trigger, so selection stays a signed action).
  def search_input
    # name="q" is the field reactive_filter(:q) compiles to [name="q"] (issue #186).
    input(**mix(
      reactive_listnav("[role=option]"),
      id: "filter-combobox-search", name: "q",
      type: "search", autocomplete: "off",
      data: { testid: "filter-query" }
    ))
  end

  def group(category, entries)
    div(data: { filter_group: "", testid: "group-#{category.downcase}" }) do
      h3 { category }
      ul { entries.each { |name, haystack| option_button(name, haystack) } }
    end
  end

  # `name`/`haystack` are explicit params (NOT `it`): the body nests Phlex
  # blocks, where a bare `it` would resolve to the wrong receiver.
  def option_button(name, haystack)
    li do
      button(**mix(
        on(:select, name:),
        role: "option",
        data: { reactive_filter_text: haystack, testid: "option-#{name.downcase}" }
      )) { name }
    end
  end

  def selection
    div(data: { testid: "filter-combobox-selection" }) { "Selected: #{@selected}" }
  end
end
