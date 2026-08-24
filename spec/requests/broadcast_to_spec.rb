# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

# Issue #185: ONE broadcast_to replaces the 11 broadcast_*_to / _to_each methods.
# The verb is a kwarg whose value is the payload; each: fans one render out to K
# keys. These assert the new method's streams are byte-identical to the removed
# calls, and that the removed names raise a guided rewrite.
RSpec.describe "broadcast_to (issue #185)", type: :request do
  include Turbo::Broadcastable::TestHelper

  let(:keys) { [["tenant:1", :counters], ["tenant:2", :counters]] }

  describe "single-key verbs" do
    it "replace: broadcasts a replace targeting the component id" do
      html = capture_turbo_stream_broadcasts("room") do
        CounterComponent.broadcast_to("room", replace: nil)
      end.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="replace"')
      expect(html).to include('target="counter"')
      expect(html).not_to include('method="morph"')
    end

    it "replace: with morph: true emits method=\"morph\"" do
      html = capture_turbo_stream_broadcasts("room") do
        CounterComponent.broadcast_to("room", replace: nil, morph: true)
      end.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="replace"')
      expect(html).to include('method="morph"')
    end

    it "update: broadcasts an update targeting the component id" do
      html = capture_turbo_stream_broadcasts("room") do
        CounterComponent.broadcast_to("room", update: nil)
      end.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="update"')
      expect(html).to include('target="counter"')
    end

    it "append: broadcasts an append to an explicit target" do
      html = capture_turbo_stream_broadcasts("room") do
        CounterComponent.broadcast_to("room", append: nil, target: "list")
      end.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="append"')
      expect(html).to include('target="list"')
    end

    it "prepend: broadcasts a prepend to an explicit target" do
      html = capture_turbo_stream_broadcasts("room") do
        CounterComponent.broadcast_to("room", prepend: nil, target: "list")
      end.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="prepend"')
      expect(html).to include('target="list"')
    end

    it "remove: broadcasts a remove of the component id" do
      html = capture_turbo_stream_broadcasts("room") do
        CounterComponent.broadcast_to("room", remove: nil)
      end.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="remove"')
      expect(html).to include('target="counter"')
    end

    it "js: broadcasts a reactive:js op stream" do
      ops = CounterComponent.new.js.add_class("#bell", "unread")
      html = capture_turbo_stream_broadcasts("room") do
        CounterComponent.broadcast_to("room", js: ops)
      end.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="reactive:js"')
      expect(html).to include("add_class")
    end
  end

  describe "the each: multi-key fan-out" do
    it "broadcasts the verb to EVERY key" do
      # rubocop:disable-next Style/ItBlockParameter -- broadcast_key is used in a nested block
      keys.each do |broadcast_key|
        html = capture_turbo_stream_broadcasts(broadcast_key) do
          CounterComponent.broadcast_to(each: keys, replace: nil)
        end.map(&:to_s).join # rubocop:disable Style/MapJoin
        expect(html).to include('action="replace"')
      end
    end

    it "renders the component EXACTLY ONCE for a K-key fan-out" do
      allow(CounterComponent).to receive(:render_component).and_call_original
      CounterComponent.broadcast_to(each: keys, replace: nil)
      expect(CounterComponent).to have_received(:render_component).once
    end

    it "makes one channel call per key" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      CounterComponent.broadcast_to(each: keys, replace: nil)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).exactly(keys.size).times
    end
  end

  describe "transport opts" do
    it "threads exclude via the pgbus thread-local (pgbus-present), no StreamsChannel kwarg" do
      allow(Phlex::Reactive).to receive(:pgbus_streams?).and_return(true)
      seen = nil
      seen_kwargs = nil
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |*_a, **kwargs|
        seen = Thread.current[:pgbus_broadcast_exclude]
        seen_kwargs = kwargs
      end

      CounterComponent.broadcast_to("room", replace: nil, exclude: "conn-1")

      expect(seen).to eq("conn-1")
      expect(seen_kwargs).not_to have_key(:exclude)
      expect(Thread.current[:pgbus_broadcast_exclude]).to be_nil # cleared after
    end
  end

  describe "module-level Phlex::Reactive.broadcast_to (issue #185)" do
    # A PLAIN (non-Streamable) component — a count badge with no #id contract.
    let(:plain_klass) do
      Class.new(Phlex::HTML) do
        def self.name = "PlainBadge"
        def initialize(count: 0) = @count = count
        def view_template = span(id: "count-badge") { @count.to_s }
      end
    end

    it "broadcasts a container verb (update:) with a plain component to an explicit target" do
      html = capture_turbo_stream_broadcasts("room") do
        Phlex::Reactive.broadcast_to("room", update: plain_klass.new(count: 5), target: "count-badge")
      end.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="update"')
      expect(html).to include('target="count-badge"')
      expect(html).to include(">5<")
    end

    it "instruments the broadcast (broadcast.phlex_reactive fires) for a plain component" do
      events = []
      sub = ActiveSupport::Notifications.subscribe("broadcast.phlex_reactive") { |*a| events << a }
      Phlex::Reactive.broadcast_to("room", update: plain_klass.new(count: 5), target: "count-badge")
      ActiveSupport::Notifications.unsubscribe(sub)
      expect(events).not_to be_empty
    end

    it "steers a self-targeting verb (replace:) with a PLAIN component to a guided error" do
      expect { Phlex::Reactive.broadcast_to("room", replace: plain_klass.new) }
        .to raise_error(ArgumentError, /update:|#id|Streamable/)
    end

    it "defaults a Streamable payload's target to its #id (replace:)" do
      html = capture_turbo_stream_broadcasts("room") do
        Phlex::Reactive.broadcast_to("room", replace: CounterComponent.new(count: 0))
      end.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('target="counter"')
    end
  end

  describe "removed method stubs (guided errors)" do
    it "broadcast_replace_to raises a guided error naming broadcast_to" do
      expect { CounterComponent.broadcast_replace_to("room", model: nil) }
        .to raise_error(NoMethodError, /broadcast_to/)
    end

    it "broadcast_replace_to_each raises a guided error naming broadcast_to(each:)" do
      expect { CounterComponent.broadcast_replace_to_each(keys, model: nil) }
        .to raise_error(NoMethodError, /broadcast_to.*each|each.*broadcast_to/m)
    end

    it "broadcast_js_to raises a guided error naming broadcast_to(js:)" do
      expect { CounterComponent.broadcast_js_to("room", CounterComponent.new.js.add_class("#x", "y")) }
        .to raise_error(NoMethodError, /broadcast_to/)
    end
  end
end
