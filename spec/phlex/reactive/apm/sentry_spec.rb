# frozen_string_literal: true

require "rails_helper"

# The Sentry adapter (issue #207). Runtime capability-detected via `::Sentry`.
# Sentry's primary value here is error reporting: an action-body crash is
# captured WITH component/action tags. record_action names the transaction.
RSpec.describe Phlex::Reactive::APM::Sentry do
  subject(:adapter) { described_class.new }

  describe ".available?" do
    it "is false when the Sentry constant is absent" do
      hide_const("Sentry") if defined?(Sentry)
      expect(described_class.available?).to be(false)
    end

    it "is true when the Sentry constant is present and initialized" do
      spy = Module.new
      spy.define_singleton_method(:initialized?) { true }
      stub_const("Sentry", spy)
      expect(described_class.available?).to be(true)
    end

    it "is false when Sentry is present but not initialized" do
      spy = Module.new
      spy.define_singleton_method(:initialized?) { false }
      stub_const("Sentry", spy)
      expect(described_class.available?).to be(false)
    end
  end

  describe "#record_error" do
    it "captures the exception with component/action tags" do
      calls = []
      spy = Module.new
      spy.define_singleton_method(:capture_exception) { |error, **opts| calls << [error, opts] }
      stub_const("Sentry", spy)
      error = RuntimeError.new("boom")

      adapter.record_error(error, { component: "Counter", action: "increment", outcome: :error })

      captured_error, opts = calls.first
      expect(captured_error).to be(error)
      expect(opts[:tags]).to include(reactive_component: "Counter", reactive_action: "increment")
    end
  end

  describe "#record_action" do
    it "sets the transaction name on the current scope when a component is present" do
      names = []
      scope = Object.new
      scope.define_singleton_method(:set_transaction_name) { names << it }
      spy = Module.new
      spy.define_singleton_method(:configure_scope) { |&blk| blk.call(scope) }
      stub_const("Sentry", spy)

      adapter.record_action({ component: "Counter", action: "increment", outcome: :ok }, 3.0)

      expect(names).to eq(["Counter#increment"])
    end
  end
end
