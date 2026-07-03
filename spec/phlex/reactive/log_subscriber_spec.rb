# frozen_string_literal: true

require "rails_helper"

# The opt-in LogSubscriber turns each hot-path event into one compact debug line
# (issue #107). Default off; attached by the engine when Phlex::Reactive.log_events
# is set. Driven here directly with synthesized events so we assert the exact
# formatted line without touching the live notification bus.
RSpec.describe Phlex::Reactive::LogSubscriber do
  def line_for(event_name, payload)
    io = StringIO.new
    logger = Logger.new(io)
    logger.level = Logger::DEBUG
    subscriber = described_class.new
    allow(subscriber).to receive(:logger).and_return(logger)
    event = ActiveSupport::Notifications::Event.new(event_name, Time.now, Time.now, "id", payload)
    subscriber.public_send(event_name.split(".").first, event)
    io.string
  end

  it "formats a successful action line" do
    line = line_for("action.phlex_reactive", component: "Counter", action: "increment", outcome: :ok)
    expect(line).to match(/\[reactive\] Counter#increment ok \(\d/)
  end

  it "formats a denied action line" do
    line = line_for("action.phlex_reactive", component: "Counter", action: "drop_table", outcome: :denied_undeclared)
    expect(line).to include("[reactive] Counter#drop_table denied_undeclared")
  end

  it "formats an invalid-token line without a trusted component name" do
    line = line_for("action.phlex_reactive", component: nil, action: "increment", outcome: :invalid_token)
    expect(line).to include("invalid_token")
    expect(line).not_to include("#increment") # no trusted component to prefix
  end

  it "formats a render line" do
    line = line_for("render.phlex_reactive", component: "Counter", bytesize: 512)
    expect(line).to match(/\[reactive\] render Counter 512B \(\d/)
  end

  it "formats a broadcast line" do
    line = line_for("broadcast.phlex_reactive", component: "Counter", stream_action: "replace", streamables: 2)
    expect(line).to match(/\[reactive\] broadcast replace Counter →2 \(\d/)
  end

  it "logs nothing when the level is above DEBUG" do
    io = StringIO.new
    logger = Logger.new(io)
    logger.level = Logger::INFO
    subscriber = described_class.new
    allow(subscriber).to receive(:logger).and_return(logger)
    event = ActiveSupport::Notifications::Event.new(
      "action.phlex_reactive", Time.now, Time.now, "id", { component: "Counter", action: "increment", outcome: :ok }
    )
    subscriber.action(event)
    expect(io.string).to be_empty
  end
end
