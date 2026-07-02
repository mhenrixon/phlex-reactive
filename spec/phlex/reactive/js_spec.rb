# frozen_string_literal: true

require "spec_helper"

# Issue #95: the client-side DOM-command builder behind on_client. Ops compile
# to a JSON array the generic controller's runOps action interprets —
# declarative DOM operations with ZERO round trip and no client state.
RSpec.describe Phlex::Reactive::JS do
  subject(:js) { described_class.new }

  describe "immutability" do
    it "returns a NEW frozen instance from every verb (chaining never mutates)" do
      chained = js.show("#a")

      expect(chained).not_to be(js)
      expect(js.ops).to be_empty # the original is untouched
      expect(chained).to be_frozen
      expect(chained.ops).to be_frozen
    end

    it "chains ops in call order" do
      ops = js.hide(".panel").show("#panel-2").ops
      expect(ops.map(&:first)).to eq(%w[hide show])
    end
  end

  describe "wire format (#to_json)" do
    it "serializes visibility ops with their selector" do
      expect(JSON.parse(js.toggle("#menu").to_json)).to eq([["toggle", { "to" => "#menu" }]])
    end

    it "serializes class ops with the class list (symbols coerced)" do
      expect(JSON.parse(js.add_class(".tab", "active", :current).to_json))
        .to eq([["add_class", { "to" => ".tab", "classes" => %w[active current] }]])
    end

    it "serializes remove_class and toggle_class the same way" do
      expect(JSON.parse(js.remove_class(".tab", "active").to_json).dig(0, 0)).to eq("remove_class")
      expect(JSON.parse(js.toggle_class(".tab", "active").to_json).dig(0, 0)).to eq("toggle_class")
    end

    it "serializes :root as the @root sentinel (the component's own root element)" do
      expect(JSON.parse(js.toggle_class(:root, "open").to_json))
        .to eq([["toggle_class", { "to" => "@root", "classes" => ["open"] }]])
    end

    it "carries global: true only when asked (root-scoped is the lean default)" do
      expect(JSON.parse(js.hide("#overlay", global: true).to_json))
        .to eq([["hide", { "to" => "#overlay", "global" => true }]])
      expect(JSON.parse(js.hide("#overlay").to_json).dig(0, 1)).not_to have_key("global")
    end
  end

  describe "argument validation (loud at render time, never silent on the client)" do
    it "rejects a target that is neither :root nor a CSS selector string" do
      expect { js.show(:menu) }.to raise_error(ArgumentError, /:root or a CSS selector/)
    end

    it "rejects a class op without at least one class" do
      expect { js.add_class(".tab") }.to raise_error(ArgumentError, /at least one class/)
    end
  end
end
