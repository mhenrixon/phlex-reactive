# frozen_string_literal: true

require "rails_helper"

# The defer token (issue #165): a purpose-scoped, short-TTL signed identity that
# authorizes exactly ONE thing — "render this component for the actor, later".
# It is deliberately NOT interchangeable with the action identity token: an
# action token must never be accepted by the defer endpoint (it would turn any
# stolen action token into a render oracle with a longer story), and a defer
# token must never invoke an action (it has no action grant at all). The
# MessageVerifier purpose string is the mechanism for both directions.
RSpec.describe "Phlex::Reactive defer token" do
  include ActiveSupport::Testing::TimeHelpers

  let(:payload) { { "c" => "CounterComponent", "s" => { "count" => 1 } } }

  after do
    # Reset the TTL a spec may have customized (writer + lazy default).
    Phlex::Reactive.defer_token_ttl = nil
  end

  describe ".sign_defer / .verify_defer" do
    it "round-trips a payload and stamps the current token version" do
      token = Phlex::Reactive.sign_defer(payload)
      verified = Phlex::Reactive.verify_defer(token)

      expect(verified["c"]).to eq("CounterComponent")
      expect(verified["s"]).to eq({ "count" => 1 })
      expect(verified["v"]).to eq(Phlex::Reactive::TOKEN_VERSION)
    end

    it "rejects a tampered token (fails closed with nil)" do
      token = Phlex::Reactive.sign_defer(payload)
      expect(Phlex::Reactive.verify_defer("#{token}x")).to be_nil
    end

    it "rejects an ACTION identity token — purpose confusion fails closed" do
      action_token = Phlex::Reactive.sign(payload)
      expect(Phlex::Reactive.verify_defer(action_token)).to be_nil
    end

    it "is rejected BY the action verifier — the reverse confusion also fails closed" do
      defer_token = Phlex::Reactive.sign_defer(payload)
      expect(Phlex::Reactive.verify(defer_token)).to be_nil
    end

    it "expires after defer_token_ttl seconds" do
      token = Phlex::Reactive.sign_defer(payload)

      travel(Phlex::Reactive.defer_token_ttl + 1) do
        expect(Phlex::Reactive.verify_defer(token)).to be_nil
      end
    end

    it "verifies inside the TTL window" do
      token = Phlex::Reactive.sign_defer(payload)

      travel(Phlex::Reactive.defer_token_ttl - 10) do
        expect(Phlex::Reactive.verify_defer(token)).not_to be_nil
      end
    end

    it "honors a customized TTL" do
      Phlex::Reactive.defer_token_ttl = 5
      token = Phlex::Reactive.sign_defer(payload)

      travel(6) { expect(Phlex::Reactive.verify_defer(token)).to be_nil }
    end
  end

  describe ".defer_token_ttl" do
    it "defaults to 120 seconds" do
      expect(Phlex::Reactive.defer_token_ttl).to eq(120)
    end
  end
end
