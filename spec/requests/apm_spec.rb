# frozen_string_literal: true

require "rails_helper"

# Turnkey APM adapters (issue #207). `Phlex::Reactive.apm =` accepts a Symbol
# (:appsignal/:sentry/:datadog), a custom adapter object, or nil (the default,
# off). A Symbol resolves to a built-in adapter LAZILY at attach time — so load
# order doesn't matter — and no-ops with ONE warning when the named SDK isn't
# loaded (the pgbus optionality invariant applied to APMs). Zero new gemspec deps.
RSpec.describe "Phlex::Reactive.apm config + APM.detect (issue #207)", type: :request do
  # Restore the lazy default after every example — remove the ivar entirely so
  # an explicit override from one example never leaks into the next.
  around do
    it.run
  ensure
    Phlex::Reactive.remove_instance_variable(:@apm) if Phlex::Reactive.instance_variable_defined?(:@apm)
  end

  describe "the config default" do
    it "defaults to nil (off)" do
      expect(Phlex::Reactive.apm).to be_nil
    end

    it "lets a Symbol stick verbatim (resolution is deferred to attach time)" do
      Phlex::Reactive.apm = :appsignal
      expect(Phlex::Reactive.apm).to eq(:appsignal)
    end

    it "lets a custom adapter object stick verbatim" do
      adapter = Object.new
      Phlex::Reactive.apm = adapter
      expect(Phlex::Reactive.apm).to be(adapter)
    end
  end

  describe "APM.detect" do
    it "returns nil and warns when a named SDK is not loaded" do
      expect(Rails.logger).to receive(:warn)
        .with(a_string_including("[phlex-reactive]", "apm = :sentry", "not loaded"))
      expect(Phlex::Reactive::APM.detect(:sentry)).to be_nil
    end

    it "returns nil and warns for an unknown Symbol" do
      expect(Rails.logger).to receive(:warn)
        .with(a_string_including("[phlex-reactive]", "unknown", "flavour"))
      expect(Phlex::Reactive::APM.detect(:flavour)).to be_nil
    end

    it "returns a custom adapter object verbatim (no resolution)" do
      adapter = Object.new
      expect(Phlex::Reactive::APM.detect(adapter)).to be(adapter)
    end

    it "returns nil for nil (off) without warning" do
      expect(Rails.logger).not_to receive(:warn)
      expect(Phlex::Reactive::APM.detect(nil)).to be_nil
    end

    it "resolves a Symbol to its built-in adapter when the SDK IS present" do
      # Stub the Appsignal adapter's availability probe so we don't need the real
      # SDK loaded — the resolver returns an instance of the built-in class.
      allow(Phlex::Reactive::APM::Appsignal).to receive(:available?).and_return(true)
      adapter = Phlex::Reactive::APM.detect(:appsignal)
      expect(adapter).to be_a(Phlex::Reactive::APM::Appsignal)
    end
  end
end
