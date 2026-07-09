# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

# Issue #215: `effect:` on broadcast_to — the per-call effect override rides
# the broadcast <turbo-stream> element as data-reactive-effect via the
# attributes: seam every Turbo::StreamsChannel verb supports (the reactive:js
# precedent). Identical on Action Cable and pgbus: the attr is markup, not a
# transport feature.
RSpec.describe "broadcast_to effect: (issue #215)", type: :request do
  include Turbo::Broadcastable::TestHelper

  def broadcast_html(&)
    capture_turbo_stream_broadcasts("room", &).map(&:to_s).join # rubocop:disable Style/MapJoin
  end

  it "stamps a replace broadcast" do
    html = broadcast_html { CounterComponent.broadcast_to("room", replace: nil, effect: :highlight) }
    expect(html).to include('action="replace"')
    expect(html).to include('data-reactive-effect="highlight"')
  end

  it "stamps a remove broadcast (the render: false path)" do
    html = broadcast_html { CounterComponent.broadcast_to("room", remove: nil, effect: :fade) }
    expect(html).to include('action="remove"')
    expect(html).to include('data-reactive-effect="fade"')
  end

  it "stamps an append broadcast to an explicit target" do
    html = broadcast_html { CounterComponent.broadcast_to("room", append: nil, target: "list", effect: :slide) }
    expect(html).to include('action="append"')
    expect(html).to include('data-reactive-effect="slide"')
  end

  it "combines with morph: on a replace" do
    html = broadcast_html { CounterComponent.broadcast_to("room", replace: nil, morph: true, effect: :highlight) }
    expect(html).to include('method="morph"')
    expect(html).to include('data-reactive-effect="highlight"')
  end

  it "omits the attr entirely without the kwarg (byte-identical wire)" do
    html = broadcast_html { CounterComponent.broadcast_to("room", replace: nil) }
    expect(html).not_to include("data-reactive-effect")
  end

  it "serializes effect: false as \"off\"" do
    html = broadcast_html { CounterComponent.broadcast_to("room", remove: nil, effect: false) }
    expect(html).to include('data-reactive-effect="off"')
  end

  it "rejects an unknown effect name at the call site" do
    expect { CounterComponent.broadcast_to("room", replace: nil, effect: :sparkle) }
      .to raise_error(ArgumentError, /sparkle/)
  end

  it "rejects effect: on a js: broadcast (a dead construct — ops are not element streams)" do
    ops = CounterComponent.new.js.add_class("#bell", "unread")
    expect { CounterComponent.broadcast_to("room", js: ops, effect: :fade) }
      .to raise_error(ArgumentError, /js/)
  end

  it "threads effect: through the module-level Phlex::Reactive.broadcast_to" do
    html = broadcast_html do
      Phlex::Reactive.broadcast_to("room", replace: CounterComponent.new(count: 0), effect: :scale)
    end
    expect(html).to include('data-reactive-effect="scale"')
  end
end
