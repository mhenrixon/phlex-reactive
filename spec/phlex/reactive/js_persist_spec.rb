# frozen_string_literal: true

require "spec_helper"

# Issue #239: the two persist client ops — persist_state writes a flat state
# bag into the root's localStorage draft; persist_clear forgets the draft.
# Both are actor-only (refused by broadcast_to(js:) — see
# spec/requests/js_broadcast_spec.rb).
RSpec.describe Phlex::Reactive::JS do
  subject(:js) { described_class.new }

  describe "#persist_state" do
    it "serializes a root-targeted op carrying the flat state bag" do
      expect(JSON.parse(js.persist_state(step: 2, mode: "wizard").to_json))
        .to eq([["persist_state", { "to" => "@root", "state" => { "step" => 2, "mode" => "wizard" } }]])
    end

    it "accepts scalar values only (String, Numeric, true/false, nil)" do
      expect(JSON.parse(js.persist_state(a: "x", b: 1.5, c: true, d: nil).to_json).dig(0, 1, "state"))
        .to eq("a" => "x", "b" => 1.5, "c" => true, "d" => nil)
    end

    it "rejects an empty bag (a dead op is a call-site bug)" do
      expect { js.persist_state }.to raise_error(ArgumentError, /persist_state/)
    end

    it "rejects nested / non-scalar values (the draft stays flat)" do
      expect { js.persist_state(step: { nested: 1 }) }.to raise_error(ArgumentError, /scalar/)
      expect { js.persist_state(tags: %w[a b]) }.to raise_error(ArgumentError, /scalar/)
    end

    it "chains" do
      ops = JSON.parse(js.persist_state(step: 1).persist_clear.to_json)
      expect(ops.map(&:first)).to eq(%w[persist_state persist_clear])
    end
  end

  describe "#persist_clear" do
    it "serializes a root-targeted op with no args" do
      expect(JSON.parse(js.persist_clear.to_json)).to eq([["persist_clear", { "to" => "@root" }]])
    end
  end
end
