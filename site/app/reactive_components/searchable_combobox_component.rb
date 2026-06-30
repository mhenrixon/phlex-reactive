# frozen_string_literal: true

# The docs site's headline reactive demo (issue #51): a searchable combobox with
# ZERO custom JavaScript. It is STATE-backed — `query` and `selected_name` ride
# in the signed identity token, never as client-trusted state. A debounced
# `search` action filters a frozen in-memory list (no DB, no PgSearch); a
# `select` action reports the chosen item back.
#
# The whole interaction is one re-render unit: each action re-renders THIS
# component into its own `#id` via `reply.morph`, which preserves the focused
# input + caret (the value the morph renders matches what the user typed) and
# rolls the signed token forward in the same stream.
class SearchableComboboxComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  # A frozen, in-memory catalogue. It is the SOURCE the server filters on every
  # action — it is never shipped to or trusted from the client. `select` checks
  # membership against it so a forged name can't become the selection.
  LANGUAGES = [
    { name: 'Ruby',       paradigm: 'Object-oriented' },
    { name: 'Smalltalk',  paradigm: 'Object-oriented' },
    { name: 'Python',     paradigm: 'Object-oriented' },
    { name: 'Elixir',     paradigm: 'Functional' },
    { name: 'Erlang',     paradigm: 'Functional' },
    { name: 'Haskell',    paradigm: 'Functional' },
    { name: 'Clojure',    paradigm: 'Functional' },
    { name: 'OCaml',      paradigm: 'Functional' },
    { name: 'Rust',       paradigm: 'Systems' },
    { name: 'C',          paradigm: 'Systems' },
    { name: 'C++',        paradigm: 'Systems' },
    { name: 'Zig',        paradigm: 'Systems' },
    { name: 'Go',         paradigm: 'Systems' },
    { name: 'TypeScript', paradigm: 'Scripting' },
    { name: 'JavaScript', paradigm: 'Scripting' },
    { name: 'Lua',        paradigm: 'Scripting' }
  ].freeze

  # Only these two values are signed into the token.
  reactive_state :query, :selected_name

  # Both actions declare a schema — only `query` / `name` reach the method, each
  # coerced to a String. An undeclared action is denied (403).
  action :search, params: { query: :string }
  action :select, params: { name: :string }

  def initialize(query: '', selected_name: nil)
    @query = query.to_s
    @selected_name = selected_name
  end

  # Render-context-free (runs before render). Stable so the component self-targets.
  def id = 'language-combobox'

  # Debounced live filter. `reply.morph` re-renders this root in place, so the
  # focused <input> and its caret survive (Idiomorph keeps the node whose value
  # already matches @query) and the token refreshes — no `reply.replace` blur.
  def search(query:)
    @query = query.to_s
    reply.morph
  end

  # Report a selection back. `name` is client-supplied, so it MUST be validated
  # against the real list before becoming state (NO trusting client input). A
  # real mutating select would also `authorize!` here and register its error in
  # Phlex::Reactive.authorization_errors.
  def select(name:)
    return reply.morph unless LANGUAGES.any? { it[:name] == name }

    @selected_name = name
    @query = name
    reply.morph
  end

  def view_template
    # reactive_root co-locates #id + the controller + the signed token on ONE
    # element (issue #48): never put id: on a child or token threading breaks.
    div(**reactive_root(class: 'flex flex-col gap-3')) do
      # The input + the floating results share a relative wrapper so the popup
      # anchors under the field (like a real combobox dropdown).
      div(class: 'relative') do
        search_field
        results if show_results?
      end
      selection_chip if selected?
    end
  end

  private

  def selected? = @selected_name.present?

  # The dropdown pops up only while the user is actively typing a search — not
  # when the field is empty, and not after a selection (when @query == the
  # chosen name). Re-rendered on every keystroke via the debounced morph, so the
  # panel appears/disappears as the query changes.
  def show_results?
    q = @query.to_s.strip
    return false if q.empty?

    q != @selected_name.to_s
  end

  # The list filtered by the current query, grouped by paradigm. Re-derived every
  # action from @query — it is NOT reactive_state (the list isn't client state).
  def filtered
    needle = @query.to_s.strip.downcase
    rows = needle.empty? ? LANGUAGES : LANGUAGES.select { it[:name].downcase.include?(needle) }
    rows.group_by { it[:paradigm] }
  end

  def search_field
    # The DEBOUNCED search trigger lives on the INPUT (input event). Its value
    # travels as the `query` param because it's a named control of this root.
    # mix() deep-merges so on()'s data-action is never clobbered (a bare data:
    # would silently unbind the action -> 403 on the next keystroke).
    input(**mix(
      on(:search, event: 'input', debounce: 200),
      type: 'text',
      name: 'query',
      value: @query,
      placeholder: 'Search languages…',
      autocomplete: 'off',
      class: 'input input-bordered w-full',
      data: { testid: 'combobox-query' }
    ))
  end

  def selection_chip
    div(class: 'badge badge-primary gap-2', data: { testid: 'combobox-selection' }) do
      plain 'Selected: '
      span { @selected_name }
    end
  end

  # The floating dropdown panel, absolutely positioned under the input. Only
  # rendered when show_results? — so it pops up while typing and collapses
  # otherwise.
  def results
    div(class: 'absolute left-0 right-0 top-full z-20 mt-1') do
      groups = filtered
      if groups.empty?
        div(class: 'bg-base-200 rounded-box border border-base-300 px-3 py-2 text-sm opacity-60 shadow-lg',
            data: { testid: 'combobox-empty' }) { 'No matches' }
        return
      end

      ul(class: 'menu bg-base-200 rounded-box border border-base-300 w-full ' \
                'max-h-64 flex-nowrap overflow-y-auto shadow-lg',
         data: { testid: 'combobox-results' }) do
        groups.each do |paradigm, langs|
          li(class: 'menu-title') { paradigm }
          langs.each { option_row(it) }
        end
      end
    end
  end

  def option_row(lang)
    li do
      # The SELECT trigger lives on the BUTTON (click), not the input — so typing
      # in the field never fires select. The explicit `name:` param wins over any
      # collected field. type="button" (forced by on for click) keeps a bare
      # button from submitting an enclosing form.
      button(**mix(
        on(:select, name: lang[:name]),
        class: 'justify-start',
        data: { testid: "combobox-option-#{lang[:name].parameterize}" }
      )) { lang[:name] }
    end
  end
end
