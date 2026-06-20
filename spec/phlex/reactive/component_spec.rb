# frozen_string_literal: true

require "spec_helper"

RSpec.describe Phlex::Reactive::Component do
  # A minimal state-backed component (no Rails/Phlex render needed for these).
  let(:state_klass) do
    Class.new do
      include Phlex::Reactive::Component
      def self.name = "StateThing"

      reactive_state :count
      action :increment
      action :set, params: { count: :integer }

      def initialize(count: 0) = @count = count
      attr_reader :count
      def increment = @count += 1
      def set(count:) = @count = count
    end
  end

  describe "action declarations (default-deny)" do
    it "registers declared actions" do
      expect(state_klass.reactive_action?(:increment)).to be(true)
      expect(state_klass.reactive_action(:set).params).to eq({ count: :integer })
    end

    it "does not register undeclared methods" do
      expect(state_klass.reactive_action?(:wat)).to be(false)
      expect(state_klass.reactive_action(:wat)).to be_nil
    end
  end

  describe "state-backed identity" do
    it "signs state into a verifiable token and rebuilds it" do
      token = state_klass.new(count: 5).send(:reactive_token)
      payload = Phlex::Reactive.verify(token)

      expect(payload["c"]).to eq("StateThing")
      expect(payload["s"]).to eq({ "count" => 5 })

      rebuilt = state_klass.from_identity(payload)
      expect(rebuilt.count).to eq(5)
    end

    it "round-trips a mutation through rebuild + action" do
      token = state_klass.new(count: 1).send(:reactive_token)
      rebuilt = state_klass.from_identity(Phlex::Reactive.verify(token))
      rebuilt.increment
      expect(rebuilt.count).to eq(2)
    end
  end

  describe "inheritance" do
    it "inherits actions and state keys from a parent" do
      child = Class.new(state_klass) do
        def self.name = "ChildThing"
        action :decrement
        def decrement = @count -= 1
      end

      expect(child.reactive_action?(:increment)).to be(true) # inherited
      expect(child.reactive_action?(:decrement)).to be(true) # own
      expect(child.reactive_state_keys).to include(:count)
      # parent unaffected
      expect(state_klass.reactive_action?(:decrement)).to be(false)
    end
  end
end
