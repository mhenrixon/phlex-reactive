# frozen_string_literal: true

require "rails_helper"

# The APM Subscriber (issue #207) is the ASN-driven half: it subscribes to
# action.phlex_reactive / defer.phlex_reactive and calls the resolved adapter's
# record_action with the component/action/outcome + duration. Driven here
# directly with synthesized events (à la log_subscriber_spec), no HTTP.
RSpec.describe Phlex::Reactive::APM::Subscriber do
  # A test adapter recording every call so we can assert what the subscriber
  # forwards — nothing more than names/outcome/duration.
  let(:adapter) do
    Class.new do
      attr_reader :actions

      def initialize = @actions = []
      def record_action(payload, duration_ms) = @actions << [payload, duration_ms]
      def record_error(_error, _payload) = nil
    end.new
  end

  after { described_class.uninstall }

  def emit(event_name, payload, duration_ms: 3.0)
    started = Time.now
    finished = started + (duration_ms / 1000.0)
    event = ActiveSupport::Notifications::Event.new(event_name, started, finished, "id", payload)
    described_class.new(adapter).public_send(event_name.split(".").first, event)
  end

  # Fire one action.phlex_reactive event through the live bus (the block is the
  # instrumented work — a no-op here; we assert what the subscriber forwarded).
  def fire_action_event
    Phlex::Reactive.instrument("action", { component: "C", action: "a", outcome: :ok }) { :done }
  end

  it "forwards a successful action to record_action with the payload + duration" do
    emit("action.phlex_reactive", { component: "Counter", action: "increment", outcome: :ok })
    expect(adapter.actions.size).to eq(1)
    payload, duration = adapter.actions.first
    expect(payload).to include(component: "Counter", action: "increment", outcome: :ok)
    expect(duration).to be_within(0.5).of(3.0)
  end

  it "forwards a defer event to record_action too" do
    emit("defer.phlex_reactive", { component: "SlowTotals", outcome: :ok })
    payload, = adapter.actions.first
    expect(payload).to include(component: "SlowTotals", outcome: :ok)
  end

  it "forwards ONLY names/outcome/sizes — never a token/params/state key" do
    emit("action.phlex_reactive", { component: "Counter", action: "set", outcome: :ok })
    payload, = adapter.actions.first
    expect(payload.keys).not_to include(:token, :params, :state)
  end

  describe ".install / .uninstall (idempotency)" do
    it "installs exactly one subscription and record_action fires once per event" do
      described_class.install(adapter)
      fire_action_event
      expect(adapter.actions.size).to eq(1)
    end

    it "re-installing with the SAME adapter does not double-subscribe" do
      described_class.install(adapter)
      described_class.install(adapter)
      fire_action_event
      expect(adapter.actions.size).to eq(1)
    end

    it "uninstall removes the subscription" do
      described_class.install(adapter)
      described_class.uninstall
      fire_action_event
      expect(adapter.actions).to be_empty
    end
  end
end
