# frozen_string_literal: true

require "rails_helper"

# The Datadog adapter (issue #207, dd-trace-rb). Runtime capability-detected via
# `::Datadog::Tracing`. record_action renames the active span + tags it;
# record_error marks the active span as errored. No-ops with no active span.
RSpec.describe Phlex::Reactive::APM::Datadog do
  subject(:adapter) { described_class.new }

  # A span spy capturing resource=/set_tag/set_error.
  def span_spy
    Object.new.tap do
      calls = []
      it.define_singleton_method(:calls) { calls }
      it.define_singleton_method(:resource=) { calls << [:resource, it] }
      it.define_singleton_method(:set_tag) { |k, v| calls << [:tag, k, v] }
      it.define_singleton_method(:set_error) { calls << [:error, it] }
    end
  end

  # Stub ::Datadog::Tracing with active_span returning `span`.
  def stub_datadog(span)
    datadog = Module.new
    datadog.define_singleton_method(:configuration) { nil }
    tracing = Module.new
    tracing.define_singleton_method(:active_span) { span }
    stub_const("Datadog", datadog)
    stub_const("Datadog::Tracing", tracing)
  end

  describe ".available?" do
    it "is false when the Datadog constant is absent" do
      hide_const("Datadog") if defined?(Datadog)
      expect(described_class.available?).to be(false)
    end

    it "is true when Datadog::Tracing is present" do
      stub_datadog(nil)
      expect(described_class.available?).to be(true)
    end
  end

  describe "#record_action" do
    it "renames the active span Component#action and tags it" do
      span = span_spy
      stub_datadog(span)

      adapter.record_action({ component: "Counter", action: "increment", outcome: :ok }, 3.0)

      expect(span.calls).to include([:resource, "Counter#increment"])
      expect(span.calls).to include([:tag, "reactive.component", "Counter"])
      expect(span.calls).to include([:tag, "reactive.outcome", "ok"])
    end

    it "no-ops when there is no active span" do
      stub_datadog(nil)

      expect { adapter.record_action({ component: "Counter", action: "increment", outcome: :ok }, 3.0) }
        .not_to raise_error
    end
  end

  describe "#record_error" do
    it "marks the active span with the error" do
      span = span_spy
      stub_datadog(span)
      error = RuntimeError.new("boom")

      adapter.record_error(error, { component: "Counter", action: "increment", outcome: :error })

      expect(span.calls).to include([:error, error])
    end
  end
end
