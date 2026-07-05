# frozen_string_literal: true

require "rails_helper"

# The Defer builder (issue #165): turns recorded reply.defer segments into wire
# streams — the pending placeholder (optional) + the delivery directive — and
# picks the lane (:fetch pull / :stream push) from defer_transport + the
# runtime capability gates. Token minting is exercised end-to-end here: the
# directive's token must round-trip through verify_defer to the SAME identity
# from_identity rebuilds.
RSpec.describe Phlex::Reactive::Defer do
  let(:component) { CounterComponent.new(count: 42) }
  let(:segment) { described_class::Segment.new(component:, placeholder: nil, morph: false) }

  after { Phlex::Reactive.defer_transport = nil }

  def stub_push_capable!
    # A configuration double exposing queue_prefix (default "pgbus"), so the key
    # minter can budget against it exactly as pgbus does.
    config = Object.new
    config.define_singleton_method(:queue_prefix) { "pgbus" }
    config.define_singleton_method(:streams_path) { nil }
    pgbus = Module.new do
      def self.stream(*) = nil

      # Mirror pgbus's own budget guard: return the key when it fits, raise
      # otherwise (pgbus does NOT shrink an arbitrary string — key.rb:101).
      def self.stream_key!(key)
        budget = Pgbus::Streams::Key.queue_name_budget
        raise ArgumentError, "over budget" if key.length > budget

        key
      end
    end
    pgbus.define_singleton_method(:configuration) { config }
    capable_stream = Class.new do
      def broadcast(payload, visible_to: nil, durable: nil, exclude: nil, event: nil,
                    coalesce: nil, target: nil)
        [payload, visible_to, durable, exclude, event, coalesce, target]
      end
    end
    key_module = Module.new do
      # pgbus's own formula: MAX(47) - queue_prefix - 1.
      def self.queue_name_budget = 47 - Pgbus.configuration.queue_prefix.length - 1
    end
    stub_const("Pgbus", pgbus)
    stub_const("Pgbus::Streams", Module.new)
    stub_const("Pgbus::Streams::Stream", capable_stream)
    stub_const("Pgbus::Streams::Key", key_module)
    stub_const("Pgbus::Streams::SignedName", Module.new do
      def self.sign(name) = "signed-#{name}"
    end)
  end

  def directive_token(html)
    raw = html[/data-reactive-defer-token="([^"]+)"/, 1]
    expect(raw).not_to be_nil
    CGI.unescapeHTML(raw)
  end

  describe ".resolve_via" do
    it "is :fetch under :auto when pgbus is absent (the default suite)" do
      skip "pgbus is loaded in this process" if defined?(Pgbus)
      expect(described_class.resolve_via).to eq(:fetch)
    end

    it "is :fetch when forced, even with push capability present" do
      stub_push_capable!
      Phlex::Reactive.defer_transport = :fetch
      expect(described_class.resolve_via).to eq(:fetch)
    end

    it "is :stream under :auto when push-capable" do
      stub_push_capable!
      expect(described_class.resolve_via).to eq(:stream)
    end

    it "degrades a forced :stream to :fetch with a warning when the capability is absent" do
      skip "pgbus is loaded in this process" if defined?(Pgbus)
      Phlex::Reactive.defer_transport = :stream

      allow(Rails.logger).to receive(:warn)
      expect(described_class.resolve_via).to eq(:fetch)
      expect(Rails.logger).to have_received(:warn).with(/defer_transport/)
    end
  end

  describe ".streams_for — the pull (:fetch) lane" do
    it "emits ONE directive stream for a keep-content segment (no placeholder)" do
      streams = described_class.streams_for(segment, via: :fetch)

      expect(streams.size).to eq(1)
      directive = streams.first
      expect(directive).to include('action="reactive:defer"')
      expect(directive).to include('target="counter"')
      expect(directive).to include('data-reactive-defer-via="fetch"')
    end

    it "wraps the directive in a Stream with structural metadata that never counts as a token refresh" do
      directive = described_class.streams_for(segment, via: :fetch).first

      expect(directive).to be_a(Phlex::Reactive::Stream)
      expect(directive.rx_action).to eq("reactive:defer")
      expect(directive.rx_target).to eq("counter")
      expect(directive.rx_carries_token?).to be(false)
    end

    it "mints a defer token that round-trips to the component's identity" do
      directive = described_class.streams_for(segment, via: :fetch).first
      payload = Phlex::Reactive.verify_defer(directive_token(directive))

      expect(payload["c"]).to eq("CounterComponent")
      expect(payload["s"]).to eq({ "count" => 42 })
      expect(payload).not_to have_key("m") # plain replace arrival — no mode key
    end

    it "stamps the morph mode into the SIGNED payload (the client cannot flip it)" do
      morph_segment = described_class::Segment.new(component:, placeholder: nil, morph: true)
      directive = described_class.streams_for(morph_segment, via: :fetch).first

      expect(Phlex::Reactive.verify_defer(directive_token(directive))["m"]).to eq("morph")
    end

    it "the minted token is NOT accepted by the ACTION verifier (purpose-scoped)" do
      directive = described_class.streams_for(segment, via: :fetch).first
      expect(Phlex::Reactive.verify(directive_token(directive))).to be_nil
    end
  end

  describe "placeholder streams" do
    it "placeholder: <String> emits a shell replace BEFORE the directive, string HTML-escaped" do
      seg = described_class::Segment.new(component:, placeholder: "<p>loading</p>", morph: false)
      streams = described_class.streams_for(seg, via: :fetch)

      expect(streams.size).to eq(2)
      shell = streams.first
      expect(shell).to include('action="replace"')
      expect(shell).to include('target="counter"')
      expect(shell).to include('id="counter"')
      expect(shell).to include('data-reactive-defer-pending="true"')
      expect(shell).to include('aria-busy="true"')
      expect(shell).to include("&lt;p&gt;loading&lt;/p&gt;") # plain String is data, not markup
      expect(streams.last).to include('action="reactive:defer"')
    end

    it "placeholder: <html_safe String> renders verbatim (intentional markup)" do
      seg = described_class::Segment.new(component:, placeholder: "<p>loading</p>".html_safe, morph: false)
      shell = described_class.streams_for(seg, via: :fetch).first

      expect(shell).to include("<p>loading</p>")
    end

    it "placeholder: <Phlex component> renders it inside the shell" do
      skeleton = Class.new(Phlex::HTML) do
        def self.name = "SkeletonProbe"
        def view_template = div(class: "skeleton") { "…" }
      end
      seg = described_class::Segment.new(component:, placeholder: skeleton.new, morph: false)
      shell = described_class.streams_for(seg, via: :fetch).first

      expect(shell).to include('<div class="skeleton">…</div>')
      expect(shell).to include('data-reactive-defer-pending="true"')
    end

    it "placeholder: true uses the component's deferred_placeholder" do
      with_placeholder = Class.new(ApplicationComponent) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "PlaceholderOwner"
        reactive_state :n
        def initialize(n: 0) = @n = n
        def id = "owner"
        def deferred_placeholder = "<span>shimmer</span>".html_safe
        def view_template = div(id:, **reactive_attrs) { @n.to_s }
      end
      seg = described_class::Segment.new(component: with_placeholder.new(n: 1), placeholder: true, morph: false)
      shell = described_class.streams_for(seg, via: :fetch).first

      expect(shell).to include("<span>shimmer</span>")
      expect(shell).to include('id="owner"')
    end

    it "placeholder: true falls back to the built-in empty shell without deferred_placeholder" do
      seg = described_class::Segment.new(component:, placeholder: true, morph: false)
      streams = described_class.streams_for(seg, via: :fetch)

      expect(streams.size).to eq(2)
      shell = streams.first
      expect(shell).to include('class="reactive-defer-placeholder"')
      expect(shell).to include('data-reactive-defer-pending="true"')
    end

    it "the shell carries NO defer token attribute (the directive owns delivery — no double fetch)" do
      seg = described_class::Segment.new(component:, placeholder: true, morph: false)
      shell = described_class.streams_for(seg, via: :fetch).first

      expect(shell).not_to include("data-reactive-defer-token")
    end
  end

  describe ".streams_for — the push (:stream) lane" do
    before do
      stub_push_capable!
      ActiveJob::Base.queue_adapter = :test
    end

    it "emits a stream directive with the signed src + since-id 0 + a fallback token" do
      directive = described_class.streams_for(segment, via: :stream).first

      expect(directive).to include('action="reactive:defer"')
      expect(directive).to include('data-reactive-defer-via="stream"')
      expect(directive).to include('data-reactive-defer-since-id="0"')
      expect(directive).to match(%r{data-reactive-defer-src="/pgbus/streams/signed-prdefer_[a-f0-9]+"})
      # A fallback token rides alongside so the client degrades to the fetch lane
      # when the pgbus client isn't loaded (no dead-end shimmer).
      expect(directive).to include("data-reactive-defer-token")
    end

    it "the stream directive's fallback token round-trips to the deferred component's identity" do
      directive = described_class.streams_for(segment, via: :stream).first
      raw = directive[/data-reactive-defer-token="([^"]+)"/, 1]

      payload = Phlex::Reactive.verify_defer(CGI.unescapeHTML(raw))
      expect(payload["c"]).to eq("CounterComponent")
    end

    it "mints a one-shot key inside pgbus's default 41-char [a-zA-Z0-9_] queue-name budget" do
      directive = described_class.streams_for(segment, via: :stream).first
      key = directive[/signed-(prdefer_[a-f0-9]+)/, 1]

      expect(key).to match(/\A[a-zA-Z0-9_]+\z/)
      expect(key.length).to be <= 41
    end

    it "fits the key to a NON-default queue_prefix (a longer prefix would overflow a fixed 40)" do
      # pgbus's budget is 47 - queue_prefix.length - 1. A 10-char prefix leaves
      # 36; a fixed prdefer_<hex16> (40) would raise StreamNameTooLong in the
      # JOB, AFTER the directive already shipped — the shimmer would hang. The
      # key must be minted against the LIVE budget.
      Pgbus.configuration.define_singleton_method(:queue_prefix) { "tenant_abc" } # 10 chars
      directive = described_class.streams_for(segment, via: :stream).first
      key = directive[/signed-(prdefer_[a-f0-9]+)/, 1]

      expect(key).not_to be_nil
      expect(key.length).to be <= (47 - "tenant_abc".length - 1) # 36
      expect(key).to match(/\Aprdefer_[a-f0-9]+\z/)
    end

    it "DEGRADES to the fetch lane when the prefix is so long the collision-safe key can't fit" do
      # budget = 47 - prefix - 1. A 24-char prefix leaves budget 22 < the
      # marker (8) + collision-safe floor (16) = 24 → no safe key fits. Rather
      # than mint an overflowing key that raises StreamNameTooLong in the JOB
      # (after the directive shipped → hung shimmer), we fall back to :fetch.
      Pgbus.configuration.define_singleton_method(:queue_prefix) { "a" * 24 }
      allow(Rails.logger).to receive(:warn)

      directive = described_class.streams_for(segment, via: :stream).first

      expect(directive).to include('data-reactive-defer-via="fetch"')
      expect(directive).to include("data-reactive-defer-token")
      expect(directive).not_to include('data-reactive-defer-via="stream"')
      expect(Rails.logger).to have_received(:warn).with(/push/)
    end

    it "enqueues the render job with the identity payload, key, target and morph mode" do
      expect do
        described_class.streams_for(
          described_class::Segment.new(component:, placeholder: nil, morph: true), via: :stream
        )
      end.to(have_enqueued_job(Phlex::Reactive::DeferredRenderJob).with do |klass, payload, key, target, morph|
        expect(klass).to eq("CounterComponent")
        expect(payload).to eq({ "c" => "CounterComponent", "s" => { "count" => 42 } })
        expect(key).to match(/\Aprdefer_[a-f0-9]+\z/)
        expect(target).to eq("counter")
        expect(morph).to be(true)
      end)
    end

    it "honors Pgbus.configuration.streams_path for the src base" do
      Pgbus.define_singleton_method(:configuration) do
        config = Object.new
        config.define_singleton_method(:streams_path) { "/custom/streams" }
        config.define_singleton_method(:queue_prefix) { "pgbus" }
        config
      end
      directive = described_class.streams_for(segment, via: :stream).first

      expect(directive).to include('data-reactive-defer-src="/custom/streams/signed-prdefer_')
    end

    it "falls back to the FETCH directive when the enqueue fails (a committed action must still reply)" do
      allow(Phlex::Reactive::DeferredRenderJob).to receive(:perform_later).and_raise(StandardError, "queue down")
      allow(Rails.logger).to receive(:warn)

      directive = described_class.streams_for(segment, via: :stream).first

      expect(directive).to include('data-reactive-defer-via="fetch"')
      expect(directive).to include("data-reactive-defer-token")
      expect(Rails.logger).to have_received(:warn).with(/push/)
    end
  end
end
