# frozen_string_literal: true

# The FORM-BUILDER shape of the tag-chip input (issue #224) — the exact
# composition a form-builder gem (phlex-forms' tag_field) renders, where the
# wire name is computed PER INSTANCE and so can't go through the class-level
# reactive_scope compile:
#
#   * reactive_tags(name: "user[tags]") — the VERBATIM bracketed wire name of
#     the hidden comma-joined field (never re-scoped).
#   * reactive_filter(input: "#user_tags_query") — the query input is targeted
#     BY ID and carries NO name: inside a real POST/GET form, a named query
#     input would submit a stray param alongside the value.
#
# Same client behavior as TagsFieldComponent (the blessed-form demo): the chip
# list is a client projection of the hidden field, adds/removes round-trip
# nothing, and the enclosing form's GET submit carries user[tags] back — the
# page echoes it AND lists any stray params, proving the name-less input
# contributed nothing.
class FormTagsFieldComponent < ApplicationComponent
  include Phlex::Reactive::ClientBindings

  # tag => haystack (synonyms included — "db" finds Postgres).
  SUGGESTIONS = {
    "Ruby" => "ruby language backend",
    "Postgres" => "postgres database db sql",
    "Hotwire" => "hotwire turbo stimulus frontend"
  }.freeze

  def initialize(tags: "", submitted: false, stray_params: [])
    # A form builder derives both per instance: object name + attribute.
    @name = "user[tags]"
    @id = "user_tags"
    @tags = tags.to_s.split(",").map(&:strip).reject(&:empty?)
    @submitted = submitted
    @stray_params = stray_params
  end

  def view_template
    div(**mix(
      # A ClientBindings root has no #id — name it explicitly.
      reactive_root(id: "#{@id}_widget", data: { testid: "form-tags-field" }),
      reactive_tags(name: @name),
      reactive_filter(input: "##{@id}_query", empty: "#form-tags-empty")
    )) do
      form(action: "/form_tags_field", method: "get", data: { turbo: false }) do
        input(type: :hidden, name: @name, id: @id, value: @tags.join(","), data: { testid: "form-tags-value" })
        chips
        chip_template
        query_input
        suggestions
        div(id: "form-tags-empty", hidden: true) { "No matches" }
        button(type: "submit", data: { testid: "form-tags-submit" }) { "Save" }
      end
      echo if @submitted
    end
  end

  private

  # Server-rendered first paint of the current tags — the SAME markup the
  # template chip carries, so the client's connect-time rebuild is invisible.
  def chips
    div(data: { reactive_tags_list: true, testid: "form-tags-chips" }) do
      @tags.each { chip(it) }
    end
  end

  def chip(tag = nil)
    span(class: "chip", data: { reactive_tag: tag, testid: "form-tag-chip" }) do
      span(data: { reactive_tag_text: true }) { tag }
      button(**(tag ? reactive_tags_remove(tag) : reactive_tags_remove), aria: { label: "Remove #{tag}" }) { "×" }
    end
  end

  def chip_template
    template(data: { reactive_tags_template: true }) { chip }
  end

  # The query input carries an ID and NO name — reactive_filter(input:) finds
  # it by id, and the enclosing form's submit can never pick it up as a param.
  def query_input
    input(**mix(
      reactive_listnav,
      reactive_tags_add,
      id: "#{@id}_query", type: "search", autocomplete: "off",
      placeholder: "Add a tag…", data: { testid: "form-tags-query" }
    ))
  end

  # `tag`/`haystack` are explicit params (NOT `it`): the body nests Phlex
  # blocks, where a bare `it` would resolve to the wrong receiver.
  def suggestions
    div do
      SUGGESTIONS.each do |tag, haystack|
        button(**mix(
          reactive_tags_option(tag),
          data: { reactive_filter_text: haystack, testid: "form-option-#{tag.downcase}" }
        )) { tag }
      end
    end
  end

  # The submit echo: the received value plus every query param that ISN'T
  # user[…] — the system spec asserts this stays empty (the name-less query
  # input contributed no stray param).
  def echo
    div(data: { testid: "form-tags-submitted" }) { "Saved: #{@tags.join(",")}" }
    div(data: { testid: "form-tags-stray" }) { @stray_params.sort.join(",") }
  end
end
