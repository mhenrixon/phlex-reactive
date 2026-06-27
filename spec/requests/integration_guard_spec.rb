# frozen_string_literal: true

require "rails_helper"

# Issue #26 part 1: a host catch-all route can shadow POST /reactive/actions, so
# every reactive POST 404s and none of the gem's controller runs — looking
# exactly like "the endpoint isn't mounted." A boot-time check surfaces the
# cause instead of leaving adopters to guess.
RSpec.describe "Reactive action route guard (issue #26)", type: :request do
  describe ".action_route_ok?" do
    it "is true when the action path resolves to the gem controller" do
      expect(Phlex::Reactive.action_route_ok?).to be(true)
    end

    it "is false when the path resolves to a DIFFERENT controller (shadowed)" do
      # Simulate a catch-all by pointing the check at a POST path the dummy app
      # routes elsewhere (nav_probe -> demos), not the gem controller.
      expect(Phlex::Reactive.action_route_ok?("/nav_probe")).to be(false)
    end

    it "is false when no route matches the path at all" do
      expect(Phlex::Reactive.action_route_ok?("/definitely/not/mounted/anywhere")).to be(false)
    end
  end

  describe ".warn_unless_action_route_mounted!" do
    it "logs a warning naming the path and the catch-all cause when shadowed" do
      logger = instance_double(Logger)
      expect(logger).to receive(:warn).with(
        a_string_including("phlex-reactive").and(
          a_string_including("/nav_probe").and(a_string_including("catch-all"))
        )
      )

      Phlex::Reactive.warn_unless_action_route_mounted!(path: "/nav_probe", logger:)
    end

    it "stays silent when the route resolves correctly" do
      logger = instance_double(Logger)
      expect(logger).not_to receive(:warn)

      Phlex::Reactive.warn_unless_action_route_mounted!(logger:)
    end
  end
end
