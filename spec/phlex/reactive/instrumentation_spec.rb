# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

# The render and broadcast hot paths emit ActiveSupport::Notifications events
# (issue #107) carrying only NAMES/sizes — never token/params/state — so an APM
# sees render time and broadcast fan-out at the component level.
RSpec.describe "render + broadcast instrumentation" do
  def capture(name)
    events = []
    sub = ActiveSupport::Notifications.subscribe(name) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  describe "render.phlex_reactive" do
    it "fires around render_component with the component name and html bytesize" do
      events = capture("render.phlex_reactive") do
        CounterComponent.render_component(CounterComponent.new(count: 1))
      end
      expect(events.size).to eq(1)
      payload = events.first.payload
      expect(payload[:component]).to eq("CounterComponent")
      expect(payload[:bytesize]).to be > 0
      expect(payload.keys).to contain_exactly(:component, :bytesize)
    end
  end

  describe "broadcast.phlex_reactive" do
    include Turbo::Broadcastable::TestHelper

    it "fires around a broadcast with the component name, stream action and streamables count" do
      events = capture("broadcast.phlex_reactive") do
        CounterComponent.broadcast_replace_to("room", :counters, model: nil, count: 3)
      end
      expect(events.size).to eq(1)
      payload = events.first.payload
      expect(payload[:component]).to eq("CounterComponent")
      expect(payload[:stream_action]).to eq("replace")
      expect(payload[:streamables]).to eq(2) # "room", :counters
      expect(payload).not_to have_key(:model)
    end

    it "fires for remove too (no rendered body)" do
      events = capture("broadcast.phlex_reactive") do
        CounterComponent.broadcast_remove_to("room", model: nil, count: 3)
      end
      expect(events.first.payload[:stream_action]).to eq("remove")
    end
  end
end
