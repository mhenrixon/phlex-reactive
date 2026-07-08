# frozen_string_literal: true

# The tag-chip input (issue #203) — reactive_tags composing reactive_filter
# (type to narrow the preloaded suggestions) and reactive_listnav (Arrow keys
# highlight, Enter picks) into a combobox/tags widget with ZERO bespoke JS and
# ZERO round trips: the value is FORM state in the hidden comma-joined field,
# so this is a CLIENT-ONLY component (ClientBindings — no token, no actions).
#
# The chip list is a client projection of the hidden field: the server renders
# the initial chips for a no-flash first paint, and the client rebuilds them
# from the <template> chip (identical markup) on every change. The enclosing
# form's GET submit carries the joined value to the server — the page echoes
# it back, proving the round trip — and Enter in the query input must NEVER
# fire that submit (the client preventDefaults).
class TagsFieldComponent < ApplicationComponent
  include Phlex::Reactive::ClientBindings

  # tag => haystack (synonyms included — "db" finds Postgres).
  SUGGESTIONS = {
    "Ruby" => "ruby language backend",
    "Rails" => "rails framework backend web",
    "Hotwire" => "hotwire turbo stimulus frontend",
    "Postgres" => "postgres database db sql",
    "Phlex" => "phlex components views frontend"
  }.freeze

  # `tags` arrives comma-joined (the hidden field's wire form — what a model
  # would store or the submitted param carries back).
  def initialize(tags: "", submitted: false)
    @tags = tags.to_s.split(",").map(&:strip).reject(&:empty?)
    @submitted = submitted
  end

  def view_template
    div(**mix(
      # A ClientBindings root has no #id — name it explicitly (the client
      # self-checks for an id at connect).
      reactive_root(id: "tags_field", data: { testid: "tags-field" }),
      reactive_tags(:tags),
      reactive_filter(:tag_query, empty: "#tags-empty")
    )) do
      form(action: "/tags_field", method: "get", data: { turbo: false }) do
        input(type: :hidden, **reactive_field(:tags), value: @tags.join(","), data: { testid: "tags-value" })
        chips
        chip_template
        query_input
        suggestions
        div(id: "tags-empty", hidden: true, data: { testid: "tags-empty" }) { "No matches" }
        button(type: "submit", data: { testid: "tags-submit" }) { "Save" }
      end
      div(data: { testid: "tags-submitted" }) { "Saved: #{@tags.join(",")}" } if @submitted
    end
  end

  private

  # Server-rendered first paint of the current tags — the SAME markup the
  # template chip carries, so the client's connect-time rebuild is invisible.
  def chips
    div(data: { reactive_tags_list: true, testid: "tags-chips" }) do
      @tags.each { chip(it) }
    end
  end

  # One chip. With a tag: the server-rendered form (remove button carries the
  # tag). Without: the template prototype (the client fills the text node and
  # the remove param per cloned chip).
  def chip(tag = nil)
    span(class: "chip", data: { reactive_tag: tag, testid: "tag-chip" }) do
      span(data: { reactive_tag_text: true }) { tag }
      button(**(tag ? reactive_tags_remove(tag) : reactive_tags_remove), aria: { label: "Remove #{tag}" }) { "×" }
    end
  end

  def chip_template
    template(data: { reactive_tags_template: true }) { chip }
  end

  # The query input drives BOTH the filter (name matches reactive_filter's
  # :tag_query) and the adds: listnav first (Enter prefers the highlighted
  # option), reactive_tags_add second (free text when nothing is highlighted).
  def query_input
    input(**mix(
      reactive_listnav,
      reactive_tags_add,
      name: "tag_query", type: "search", autocomplete: "off",
      placeholder: "Add a tag…", data: { testid: "tags-query" }
    ))
  end

  # `tag`/`haystack` are explicit params (NOT `it`): the body nests Phlex
  # blocks, where a bare `it` would resolve to the wrong receiver.
  def suggestions
    div do
      SUGGESTIONS.each do |tag, haystack|
        button(**mix(
          reactive_tags_option(tag),
          data: { reactive_filter_text: haystack, testid: "option-#{tag.downcase}" }
        )) { tag }
      end
    end
  end
end
