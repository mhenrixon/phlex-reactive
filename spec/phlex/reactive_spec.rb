# frozen_string_literal: true

require "spec_helper"

RSpec.describe Phlex::Reactive do
  describe ".sign / .verify" do
    it "round-trips a payload" do
      payload = {"c" => "Demo::Counter", "s" => {"count" => 3}}
      token = described_class.sign(payload)
      expect(described_class.verify(token)).to eq(payload)
    end

    it "rejects a tampered token" do
      token = described_class.sign({"c" => "X", "s" => {}})
      expect(described_class.verify("#{token}x")).to be_nil
    end

    it "rejects a token signed with a different key" do
      other = ActiveSupport::MessageVerifier.new("different")
      forged = other.generate({"c" => "Evil"}, purpose: described_class::IDENTITY_PURPOSE)
      expect(described_class.verify(forged)).to be_nil
    end

    it "rejects a token signed for a different purpose" do
      token = described_class.verifier.generate({"c" => "X"}, purpose: "other")
      expect(described_class.verify(token)).to be_nil
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
