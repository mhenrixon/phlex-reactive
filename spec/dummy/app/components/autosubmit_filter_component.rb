# frozen_string_literal: true

# Issue #226: the GENERAL autosubmit story — a plain GET filter form whose
# select submits it on change via the client-side submit op:
#
#   select(**on_client(:change, js.submit("form")))
#
# No bespoke Stimulus controller, no reactive action, no token — the ONE line
# replaces the classic onchange="this.form.requestSubmit()". requestSubmit
# fires a real submit event, so Turbo Drive turns it into a visit (the page
# updates without a full reload — the system spec's window marker survives).
class AutosubmitFilterComponent < ApplicationComponent
  include Phlex::Reactive::Component

  def initialize(sort: "name")
    @sort = sort
  end

  def id = "autosubmit-filter"

  def view_template
    div(id:, **reactive_attrs) do
      form(action: "/autosubmit_filter", method: "get", data: { testid: "filter-form" }) do
        select(name: "sort", **mix(on_client(:change, js.submit("form")), data: { testid: "sort" })) do
          option(value: "name", selected: @sort == "name") { "Name" }
          option(value: "price", selected: @sort == "price") { "Price" }
        end
      end
      p(data: { testid: "sorted-by" }) { "Sorted by: #{@sort}" }
    end
  end
end
