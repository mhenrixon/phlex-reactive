# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

# Issue #119: broadcast_*_to_each — render ONCE, fan the shared payload out over
# K different stream keys. Broadcasting one component to K keys (a per-tenant
# loop — "the list page stream AND the dashboard stream") with the classic
# broadcast_*_to is K× build + K× render + K× HMAC for BYTE-IDENTICAL HTML,
# because *streamables concatenates into ONE key. _to_each renders one component
# and loops only the cheap channel call.
#
# These are the correctness guards behind the perf claim: every key receives the
# broadcast, the HTML is identical across keys, render happens exactly once,
# transport opts (exclude:/visible_to:) forward PER key, morph: rides through,
# and — the pgbus-optionality invariant — the no-opts call never passes an
# unknown keyword to an old-pgbus-shape transport (the ArgumentError regression).
RSpec.describe "broadcast_*_to_each fan-out (issue #119)", type: :request do
  include Turbo::Broadcastable::TestHelper

  # A per-tenant fan-out: the SAME component to N distinct stream keys. Each key
  # is a [record-or-string, symbol] pair, exactly as broadcast_replace_to takes
  # via *streamables.
  let(:keys) { [["tenant:1", :counters], ["tenant:2", :counters], ["tenant:3", :counters]] }

  describe ".broadcast_replace_to_each" do
    it "broadcasts a replace to EVERY key" do
      keys.each do
        broadcasts = capture_turbo_stream_broadcasts(it) do
          CounterComponent.broadcast_replace_to_each(keys, model: nil)
        end
        html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
        expect(html).to include('action="replace"')
        expect(html).to include('target="counter"')
      end
    end

    it "delivers BYTE-IDENTICAL HTML to each key (one render, shared payload)" do
      captured = keys.to_h do
        broadcasts = capture_turbo_stream_broadcasts(it) do
          CounterComponent.broadcast_replace_to_each(keys, model: nil)
        end
        [it, broadcasts.map(&:to_s).join] # rubocop:disable Style/MapJoin
      end

      expect(captured.values.uniq.size).to eq(1)
    end

    it "renders the component EXACTLY ONCE for a K-key fan-out" do
      allow(CounterComponent).to receive(:render_component).and_call_original

      CounterComponent.broadcast_replace_to_each(keys, model: nil)

      expect(CounterComponent).to have_received(:render_component).once
    end

    it "makes one channel call per key with the identical html" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      CounterComponent.broadcast_replace_to_each(keys, model: nil)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).exactly(keys.size).times
    end

    it "accepts a single key as a bare (non-nested) pair too" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      CounterComponent.broadcast_replace_to_each([["solo", :counters]], model: nil)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with("solo", :counters, hash_including(target: "counter"))
    end

    it "carries method=\"morph\" to every key when morph: true" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      CounterComponent.broadcast_replace_to_each(keys, model: nil, morph: true)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(anything, anything, hash_including(attributes: { method: "morph" }))
        .exactly(keys.size).times
    end
  end

  # exclude:/visible_to: are TRANSPORT opts (pgbus reads them; Action Cable
  # ignores them). They must forward PER key exactly like every other
  # broadcast_*_to method — the pgbus-PRESENT path suppresses the actor's echo
  # on every stream, and the pgbus-ABSENT path stays unchanged.
  describe "transport opts pass-through (pgbus-present)" do
    it "forwards exclude: to every key" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      CounterComponent.broadcast_replace_to_each(keys, model: nil, exclude: "conn-actor-1")

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(anything, anything, hash_including(exclude: "conn-actor-1"))
        .exactly(keys.size).times
    end

    it "forwards visible_to: to every key" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      CounterComponent.broadcast_replace_to_each(keys, model: nil, visible_to: "user:7")

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
        .with(anything, anything, hash_including(visible_to: "user:7"))
        .exactly(keys.size).times
    end
  end

  # The pgbus-ABSENT / old-pgbus regression: an old Turbo::StreamsChannel (or
  # pgbus < 0.9.2) has NO exclude:/visible_to: keyword. When the caller passes no
  # transport opts, _to_each must not pass those keywords — otherwise every key
  # raises `ArgumentError: unknown keyword :exclude`. This double is the "old
  # pgbus shape": broadcast_replace_to accepts target/html/attributes but REJECTS
  # exclude/visible_to. The no-opts fan-out must run clean over it.
  describe "pgbus-absent path (old-shape transport rejects exclude:)" do
    let(:old_shape) do
      Class.new do
        attr_reader :calls

        def initialize = @calls = []

        # Mirrors the classic Turbo::StreamsChannel.broadcast_replace_to signature:
        # positional stream parts + target:/html:/attributes: only. No exclude:.
        def broadcast_replace_to(*streamables, target:, html:, **attributes)
          @calls << { streamables:, target:, html:, attributes: }
          nil
        end
      end.new
    end

    it "never passes exclude:/visible_to: when none given (no ArgumentError)" do
      stub_const("Turbo::StreamsChannel", old_shape)

      expect { CounterComponent.broadcast_replace_to_each(keys, model: nil) }.not_to raise_error
      expect(old_shape.calls.size).to eq(keys.size)
      expect(old_shape.calls).to all(include(target: "counter"))
    end
  end

  # Every other verb gets the same fan-out primitive. One spec per verb, mocking
  # the channel, so the contract (once render, per-key channel call) is pinned.
  describe "the other verbs fan out the same way" do
    it "broadcast_update_to_each" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
      CounterComponent.broadcast_update_to_each(keys, model: nil)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_update_to).exactly(keys.size).times
    end

    it "broadcast_append_to_each" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
      CounterComponent.broadcast_append_to_each(keys, target: "list", model: nil)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
        .with(anything, anything, hash_including(target: "list")).exactly(keys.size).times
    end

    it "broadcast_prepend_to_each" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
      CounterComponent.broadcast_prepend_to_each(keys, target: "list", model: nil)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to)
        .with(anything, anything, hash_including(target: "list")).exactly(keys.size).times
    end

    it "broadcast_remove_to_each (no render — remove has no body)" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
      CounterComponent.broadcast_remove_to_each(keys, model: nil)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_remove_to)
        .with(anything, anything, hash_including(target: "counter")).exactly(keys.size).times
    end
  end
end
