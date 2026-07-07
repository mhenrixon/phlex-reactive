# frozen_string_literal: true

# A searchable combobox exercising client-side list navigation (issue #72).
#
# State-backed: `query` and `selected` ride in the signed token. `search` filters
# a frozen in-memory list server-side (debounced); `select` records the choice.
# The search input composes `reactive_listnav` (issue #181 — the `on(…, listnav:)`
# kwarg was removed), so the generic controller wires Arrow Up/Down (move a
# client-side highlight — NO round trip), Enter (pick the highlighted option by
# clicking its own on(:select) trigger), and Escape (clear) onto the input.
# Selection stays a signed reactive action; only the highlight is ephemeral
# client state.
class ComboboxComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  FRUITS = %w[Apple Apricot Banana Blueberry Cherry Cranberry Grape Mango Orange Peach].freeze

  reactive_state :query, :selected
  action :search, params: { query: :string }
  action :select, params: { name: :string }

  def initialize(query: "", selected: nil)
    @query = query.to_s
    @selected = selected
  end

  def id = "combobox"

  def search(query:)
    @query = query.to_s
    reply.morph
  end

  def select(name:)
    return reply.morph unless FRUITS.include?(name)

    @selected = name
    @query = name
    reply.morph
  end

  def view_template
    div(**reactive_root(data: { testid: "combobox" })) do
      input(**mix(
        on(:search, event: "input", debounce: 100),
        reactive_listnav,
        type: "text", name: "query", value: @query, autocomplete: "off",
        data: { testid: "combobox-query" }
      ))
      results
      selection if @selected.present?
    end
  end

  private

  def filtered
    needle = @query.to_s.strip.downcase
    return [] if needle.empty? || needle == @selected.to_s.downcase

    FRUITS.select { it.downcase.include?(needle) }
  end

  def results
    ul(data: { testid: "combobox-results" }) do
      each_option { option_button(it) }
    end
  end

  def each_option(&) = filtered.each(&)

  # `fruit` is an explicit param (NOT `it`): the body nests Phlex blocks, where a
  # bare `it` would resolve to the wrong receiver and serialize a whole component
  # into the action params — an infinite render recursion.
  def option_button(fruit)
    li do
      # Each option is a reactive select trigger AND a listnav target
      # ([role=option]). Enter on the input clicks the highlighted one.
      button(**mix(
        on(:select, name: fruit),
        role: "option",
        data: { testid: "option-#{fruit.downcase}" }
      )) { fruit }
    end
  end

  def selection
    div(data: { testid: "combobox-selection" }) { "Selected: #{@selected}" }
  end
end
