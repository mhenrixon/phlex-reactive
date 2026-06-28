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
      expect(CounterComponent.turbo_stream_builder).to be(CounterComponent.turbo_stream_builder)
    end
  end

  describe "render output is unchanged by memoization (back-compat)" do
    it "produces the same replace stream as a freshly-built context" do
      memoized = CounterComponent.new(count: 1).to_stream_replace
      CounterComponent.reset_turbo_view_context!
      fresh = CounterComponent.new(count: 1).to_stream_replace

      # Strip the signed token (it re-randomizes per call) before comparing.
      strip = ->(s) { s.gsub(/data-reactive-token-value="[^"]*"/, "TOKEN") }
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
end
