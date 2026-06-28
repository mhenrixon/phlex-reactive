# frozen_string_literal: true

require "rails_helper"

# Performance: building a Turbo::Streams::TagBuilder needs a real Rails view
# context, and a view context is EXPENSIVE to build (it instantiates the
# renderer controller and assembles the helper module set). The naive code
# rebuilt one on EVERY render and EVERY broadcast — the single hottest
# server-side allocation in the action round trip. These specs pin the
# memoization: the view context (and the builder bound to it) is reused across
# renders, but a swap of Phlex::Reactive.renderer (and, in a Rails app, a code
# reload) invalidates the cache so we never serve a stale controller instance.
RSpec.describe "Streamable view-context memoization (performance)" do
  after { CounterComponent.reset_turbo_view_context! }

  describe ".turbo_view_context" do
    it "reuses the same view context across calls" do
      first = CounterComponent.turbo_view_context
      second = CounterComponent.turbo_view_context
      expect(second).to be(first)
    end

    it "rebuilds after an explicit reset (the Rails reload hook)" do
      first = CounterComponent.turbo_view_context
      CounterComponent.reset_turbo_view_context!
      expect(CounterComponent.turbo_view_context).not_to be(first)
    end

    it "rebuilds when the configured renderer changes" do
      original = Phlex::Reactive.renderer
      first = CounterComponent.turbo_view_context

      dedicated = Class.new(ActionController::Base)
      Phlex::Reactive.renderer = dedicated
      begin
        expect(CounterComponent.turbo_view_context).not_to be(first)
      ensure
        Phlex::Reactive.renderer = original
        CounterComponent.reset_turbo_view_context!
      end
    end
  end

  describe ".turbo_stream_builder" do
    it "reuses the builder (and therefore its view context) across calls" do
      # Both sides are the SAME call on purpose: the test proves the memo returns
      # the identical object across calls, so identical expressions are the point.
      first = CounterComponent.turbo_stream_builder
      expect(CounterComponent.turbo_stream_builder).to be(first)
    end
  end

  # The cache is PER THREAD, not one-per-process: an ActionView context carries
  # mutable output_buffer/view_flow state (render_in's capture swaps it), so a
  # single shared instance could interleave content between concurrent renders
  # on a threaded server. Each thread must get its own context, and concurrent
  # renders must never corrupt each other.
  describe "thread safety" do
    it "gives each thread its own view context" do
      contexts = Queue.new
      [Thread.new { contexts << CounterComponent.turbo_view_context },
       Thread.new { contexts << CounterComponent.turbo_view_context }].each(&:join)
      a = contexts.pop
      b = contexts.pop
      expect(a).not_to be(b) # distinct instances per thread
    end

    it "renders correctly under concurrent threads (no buffer interleave)" do
      renders_per_thread = 20
      thread_count = 8
      results = Queue.new
      threads = Array.new(thread_count) do
        Thread.new do
          renders_per_thread.times do
            html = CounterComponent.render_component(CounterComponent.new(count: it))
            results << (html.include?(">#{it}<") && html.scan('id="counter"').size == 1)
          end
        end
      end
      # #value (not #join) re-raises any exception from a worker thread — a render
      # that crashed mid-thread would otherwise be swallowed AND shrink the queue,
      # letting all(be(true)) pass on the survivors. Then assert the EXACT count
      # so a partial run can't masquerade as a clean one.
      threads.each(&:value)

      expected = thread_count * renders_per_thread
      expect(results.size).to eq(expected)
      verdicts = Array.new(expected) { results.pop }
      expect(verdicts).to all(be(true))
    end
  end

  describe "render output is unchanged by memoization (back-compat)" do
    it "produces the same replace stream as a freshly-built context" do
      memoized = CounterComponent.new(count: 1).to_stream_replace
      CounterComponent.reset_turbo_view_context!
      fresh = CounterComponent.new(count: 1).to_stream_replace

      # Strip the signed token (it re-randomizes per call) before comparing.
      strip = -> { it.gsub(/data-reactive-token-value="[^"]*"/, "TOKEN") }
      expect(strip.call(memoized)).to eq(strip.call(fresh))
    end
  end

  # render_component renders through phlex-rails' lightweight render_in (a direct
  # component.call against the memoized view context) instead of the heavyweight
  # ActionController renderer.render — ~2x faster, ~half the allocations — while
  # keeping the SAME HTML and full Rails helper access (dom_id/url_for/t/csrf).
  describe ".render_component (lightweight render path)" do
    let(:todo) { Todo.create!(title: "t", done: false) }

    it "renders a state-backed component to HTML" do
      html = CounterComponent.render_component(CounterComponent.new(count: 3))
      expect(html).to include('id="counter"')
      expect(html).to include(">3<")
    end

    it "keeps Rails helpers working (dom_id on a record-backed component)" do
      html = TodoItemComponent.render_component(TodoItemComponent.new(todo:))
      expect(html).to include(%(id="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "carries the signed identity token (reactive_attrs rendered)" do
      html = CounterComponent.render_component(CounterComponent.new(count: 0))
      expect(html).to include("data-reactive-token-value=")
      expect(html).to include('data-controller="reactive"')
    end
  end

  # Issue #42: the off-request view context lost the `request` when 0.4.0 swapped
  # to `controller.new.view_context`, so any request-dependent helper
  # (form_authenticity_token, protect_against_forgery?, host-aware URL helpers)
  # raised "undefined method 'env' for nil" on every re-render and broadcast.
  # The cached context must be bound to a request so those helpers keep working.
  describe "request-dependent helpers (issue #42)" do
    let(:todo) { Todo.create!(title: "t", done: false) }

    it "exposes a request on the cached view context's controller" do
      expect(CounterComponent.turbo_view_context.controller.request).not_to be_nil
    end

    it "renders a component that calls form_authenticity_token without raising" do
      expect { CsrfFormComponent.render_component(CsrfFormComponent.new(todo:)) }
        .not_to raise_error
    end

    it "renders the authenticity token field into the HTML" do
      html = CsrfFormComponent.render_component(CsrfFormComponent.new(todo:))
      expect(html).to include('name="authenticity_token"')
    end

    it "answers protect_against_forgery? without raising (request present)" do
      expect { CounterComponent.turbo_view_context.protect_against_forgery? }
        .not_to raise_error
    end

    # The issue's second failure mode: a component rendering a host-aware path
    # (an Action with a full URL). When the renderer is a real app controller
    # (one with routes + default_url_options, as in a real app), the request
    # picks up the host so `*_url` helpers resolve instead of raising. We mutate
    # the host on the route set's default_url_options and restore it EXACTLY —
    # deleting the key if it was absent rather than setting it to nil, because a
    # `{ host: nil }` differs from `{}` and makes default_env recompute with a nil
    # host ("Missing host to link to!"), leaking into every other example. The
    # route set recomputes default_env automatically once the options match again.
    it "resolves host-aware URL helpers when the renderer has routes" do
      routed = DemosController # a real app controller — carries the app routes
      opts = Rails.application.routes.default_url_options
      had_host = opts.key?(:host)
      previous_host = opts[:host]
      opts[:host] = "example.test"

      vc = Phlex::Reactive.request_bound_view_context(routed)
      expect(vc.controller.request.host).to eq("example.test")
      name = Rails.application.routes.named_routes.names.first
      expect(vc.public_send("#{name}_url")).to start_with("http://example.test/")
    ensure
      had_host ? (opts[:host] = previous_host) : opts.delete(:host)
    end
  end

  # The standalone off-request render path (Phlex::Reactive.render — used for a
  # Response#with embedded component) shares the same regression: it must also
  # carry a request so an embedded CSRF form renders.
  describe "Phlex::Reactive.render request-dependent helpers (issue #42)" do
    let(:todo) { Todo.create!(title: "t", done: false) }

    it "exposes a request on the standalone off-request view context" do
      expect(Phlex::Reactive.off_request_view_context.controller.request).not_to be_nil
    end

    it "renders an embedded CSRF form without raising" do
      expect { Phlex::Reactive.render(CsrfFormComponent.new(todo:)) }.not_to raise_error
    end
  end
end
