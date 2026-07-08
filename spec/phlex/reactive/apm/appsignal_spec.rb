# frozen_string_literal: true

require "rails_helper"

# The AppSignal adapter (issue #207) is runtime capability-detected — it activates
# ONLY when `::Appsignal` is defined. We stub the constant (the house pattern for
# an absent optional dep, à la the pgbus specs) so the suite needs no real SDK;
# the .available? probe is the regression guard for the "SDK not loaded" path.
RSpec.describe Phlex::Reactive::APM::Appsignal do
  subject(:adapter) { described_class.new }

  # A spy standing in for the ::Appsignal module. Its `calls` array is captured in
  # the closure (no class ivars) and each singleton method mirrors the real
  # AppSignal API (set_action/add_tags/set_error — the `set_` names are the SDK's,
  # not ours). Returns the spy; read `spy.calls` to assert what the adapter forwarded.
  def stub_appsignal
    calls = []
    spy = Module.new
    spy.define_singleton_method(:calls) { calls }
    spy.define_singleton_method(:set_action) { calls << [:set_action, it] }
    spy.define_singleton_method(:add_tags) { calls << [:add_tags, it] }
    spy.define_singleton_method(:set_error) { |error, tags| calls << [:set_error, error, tags] }
    stub_const("Appsignal", spy)
    spy
  end

  describe ".available?" do
    it "is false when the Appsignal constant is absent" do
      hide_const("Appsignal") if defined?(Appsignal)
      expect(described_class.available?).to be(false)
    end

    it "is true when the Appsignal constant is present" do
      stub_const("Appsignal", Module.new)
      expect(described_class.available?).to be(true)
    end
  end

  describe "#record_action" do
    it "names the transaction Component#action and tags component/action/outcome" do
      appsignal = stub_appsignal

      adapter.record_action({ component: "Counter", action: "increment", outcome: :ok }, 3.0)

      expect(appsignal.calls).to include([:set_action, "Counter#increment"])
      tags = appsignal.calls.assoc(:add_tags).last
      expect(tags).to include("reactive_component" => "Counter", "reactive_action" => "increment",
        "reactive_outcome" => "ok")
    end

    it "no-ops silently when there is no trusted component (invalid_token)" do
      appsignal = stub_appsignal

      adapter.record_action({ component: nil, action: "increment", outcome: :invalid_token }, 1.0)

      expect(appsignal.calls).to be_empty
    end
  end

  describe "#record_error" do
    it "reports the exception with component/action tags" do
      appsignal = stub_appsignal
      error = RuntimeError.new("boom")

      adapter.record_error(error, { component: "Counter", action: "increment", outcome: :error })

      call = appsignal.calls.assoc(:set_error)
      expect(call[1]).to be(error)
      expect(call[2]).to include("reactive_component" => "Counter", "reactive_action" => "increment")
    end
  end
end
