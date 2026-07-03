# frozen_string_literal: true

require "spec_helper"

RSpec.describe Phlex::Reactive do
  describe ".sign / .verify" do
    it "round-trips a payload, stamping the current token version" do
      payload = { "c" => "Demo::Counter", "s" => { "count" => 3 } }
      token = described_class.sign(payload)
      expect(described_class.verify(token)).to eq(payload.merge("v" => described_class::TOKEN_VERSION))
    end

    it "rejects a tampered token" do
      token = described_class.sign({ "c" => "X", "s" => {} })
      expect(described_class.verify("#{token}x")).to be_nil
    end

    it "rejects a token signed with a different key" do
      other = ActiveSupport::MessageVerifier.new("different")
      forged = other.generate({ "c" => "Evil" }, purpose: described_class::IDENTITY_PURPOSE)
      expect(described_class.verify(forged)).to be_nil
    end

    it "rejects a token signed for a different purpose" do
      token = described_class.verifier.generate({ "c" => "X" }, purpose: "other")
      expect(described_class.verify(token)).to be_nil
    end
  end

  describe "token versioning (#111)" do
    # Sign a payload directly (no "v" stamp) to simulate a token minted by a
    # deploy BEFORE versioning existed, or a hand-forged shape at a given version.
    def raw_sign(payload)
      described_class.verifier.generate(payload, purpose: described_class::IDENTITY_PURPOSE)
    end

    after { described_class.reset_token_upgraders! }

    it "stamps the current version into every signed token" do
      payload = described_class.verify(described_class.sign({ "c" => "X" }))
      expect(payload["v"]).to eq(described_class::TOKEN_VERSION)
    end

    it "passes a versionless (v0) token through unchanged — versioning invalidates nothing in flight" do
      # A token from before this change: no "v" key. It still verifies, and
      # upgrade_token must treat it as today's shape (v0) and return it as-is.
      legacy = raw_sign({ "c" => "Demo::Counter", "s" => { "count" => 3 } })
      expect(described_class.verify(legacy)).to eq({ "c" => "Demo::Counter", "s" => { "count" => 3 } })
    end

    it "runs a registered upgrader to rewrite an older shape (oldest → current)" do
      # A future v0 → v1 migration: e.g. the state key was renamed count → n.
      described_class.register_token_upgrader(0) do
        it.merge("s" => { "n" => it.dig("s", "count") })
      end
      legacy = raw_sign({ "c" => "Demo::Counter", "s" => { "count" => 3 } }) # no "v" => v0

      upgraded = described_class.verify(legacy)
      expect(upgraded.dig("s", "n")).to eq(3)
      expect(upgraded["v"]).to eq(described_class::TOKEN_VERSION) # stamped to current after upgrade
    end

    it "fails closed on a token from a NEWER version than we understand (rolled-back deploy)" do
      # A newer deploy minted v=99; this older code must not guess — return nil so
      # the endpoint's `|| raise(InvalidToken)` turns it into a 400.
      future = raw_sign({ "c" => "X", "v" => described_class::TOKEN_VERSION + 98 })
      expect(described_class.verify(future)).to be_nil
    end

    it "fails closed on a signed token whose \"v\" is not an integer" do
      # "v" lives inside the signed blob, so only our own signing key (or an
      # operator error) could produce a non-integer "v". Rather than 500 on the
      # `version > TOKEN_VERSION` comparison (String vs Integer), reject → 400.
      malformed = raw_sign({ "c" => "X", "v" => "1" })
      expect(described_class.verify(malformed)).to be_nil
    end

    it "fails closed on a signed token whose \"v\" is negative" do
      # A negative "v" is not a shape we ever minted; treat it as unrecognized and
      # reject rather than silently passing it through the legacy path.
      malformed = raw_sign({ "c" => "X", "v" => -1 })
      expect(described_class.verify(malformed)).to be_nil
    end

    it "still returns nil for a genuinely invalid signature (versioning didn't change this)" do
      expect(described_class.verify("not-a-real-token")).to be_nil
    end
  end

  describe "configuration" do
    it "defaults the action path" do
      expect(described_class.action_path).to eq("/reactive/actions")
    end

    it "defaults the base controller name" do
      expect(described_class.base_controller_name).to eq("ActionController::Base")
    end
  end
end
