# frozen_string_literal: true

# Issue #199 repro: a freshly-rendered compute root that SELF-SEEDS on connect.
#
# Unlike PostPreviewComponent (which server-renders its derived counter so the
# first paint is already correct), this component deliberately renders its two
# derived outputs + its cross-root mirror BLANK — the exact shape from the issue:
# an app that relies on the client to compute the first paint. Before issue #199
# those nodes stayed blank until the first user edit (and a synthetic seed
# `input` under-applied — only the first output painted). With the connect-time
# seed, connect() runs ONE full recompute so both outputs AND the mirror paint
# from a single reducer result, no user interaction, no round trip.
#
# It is a CLIENT-ONLY component (no reactive_record / reactive_state) — there is
# no server truth to reconcile against; the whole point is the client seed.
class ComputeSeedComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  # Two numeric outputs (total, half) + a DISABLED computed twin (total_ro, issue
  # #204) + a cross-root text mirror (total_label) — the issue's minimal repro. The
  # reducer returns ALL keys every pass. total_ro is rendered `disabled`: the
  # reducer sets its `.value` PROPERTY (never the attribute), so have_reactive_value
  # must read the property to see it — the bug #204 fixes.
  reactive_compute :sums,
    inputs: %i[a b],
    outputs: %i[total half total_ro],
    mirror: { total_label: "#seed-total-label" }

  # Fixed seed values (2 + 4): the fixture always renders the same repro. The
  # compute INPUT names are `a`/`b` (the wire, class-level above); the render just
  # needs the seeded field values, so no short-named ctor params.
  def initialize(first: 2, second: 4)
    @first = first
    @second = second
  end

  def id = "compute-seed"

  def view_template
    div(**reactive_root(compute: :sums)) do
      # The two inputs carry the seed values; the derived fields render BLANK, so
      # a passing spec PROVES the connect seed painted them (not the server).
      input(**reactive_field(:a, value: @first, type: "number", data: { testid: "a" }))
      input(**reactive_field(:b, value: @second, type: "number", data: { testid: "b" }))
      input(**reactive_field(:total, value: "", type: "number", data: { testid: "total" }))
      input(**reactive_field(:half, value: "", type: "number", data: { testid: "half" }))
      # A DISABLED computed twin (issue #204): the reducer sets its `.value`
      # property, but the value ATTRIBUTE stays "" — the exact field
      # have_field(with:) can't see and have_reactive_value must (via the property).
      input(**reactive_field(:total_ro, value: "", type: "number", disabled: true, data: { testid: "total-ro" }))
    end
  end
end
