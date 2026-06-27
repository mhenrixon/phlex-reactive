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
      action :set, params: {count: :integer}

      def initialize(count: 0) = @count = count
      attr_reader :count
      def increment = @count += 1
      def set(count:) = @count = count
    end
  end

  describe "action declarations (default-deny)" do
    it "registers declared actions" do
      expect(state_klass.reactive_action?(:increment)).to be(true)
      expect(state_klass.reactive_action(:set).params).to eq({count: :integer})
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
      expect(payload["s"]).to eq({"count" => 5})

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

  describe "record + state identity (issue #6)" do
    # A record-backed component that ALSO carries transient state (which field,
    # what mode) — exactly the documented inline_edit pattern. Before the fix,
    # the state branch was dead whenever a record was present: `attribute`/
    # `editing` were never signed and never restored, so the mode reset to its
    # initialize default on every action.
    let(:record_state_klass) do
      Class.new do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "InlineThing"

        reactive_record :record
        reactive_state :attribute, :editing

        def initialize(record:, attribute:, editing: false)
          @record = record
          @attribute = attribute.to_sym
          @editing = editing
        end

        attr_reader :record, :attribute, :editing

        def id = "inline-#{@record.object_id}"
      end
    end

    # A stand-in record that round-trips through GlobalID without a DB.
    let(:record) { Struct.new(:gid_string).new("gid://app/Article/1") }

    before do
      allow(record).to receive(:to_gid).and_return(
        instance_double(GlobalID, to_s: record.gid_string)
      )
      allow(GlobalID::Locator).to receive(:locate).with(record.gid_string).and_return(record)
    end

    it "signs BOTH the record gid and the declared state into one token" do
      component = record_state_klass.new(record:, attribute: :name, editing: true)
      payload = Phlex::Reactive.verify(component.send(:reactive_token))

      expect(payload["c"]).to eq("InlineThing")
      expect(payload["gid"]).to eq(record.gid_string)
      expect(payload["s"]).to eq({"attribute" => "name", "editing" => true})
    end

    it "restores the record AND the state on rebuild (round trip)" do
      token = record_state_klass.new(record:, attribute: :name, editing: true).send(:reactive_token)
      rebuilt = record_state_klass.from_identity(Phlex::Reactive.verify(token))

      expect(rebuilt.record).to be(record)
      expect(rebuilt.attribute).to eq(:name) # not nil — survives the round trip
      expect(rebuilt.editing).to be(true)    # not the initialize default (false)
    end

    it "preserves a false state value rather than dropping to the default" do
      token = record_state_klass.new(record:, attribute: :name, editing: false).send(:reactive_token)
      rebuilt = record_state_klass.from_identity(Phlex::Reactive.verify(token))

      expect(rebuilt.editing).to be(false)
    end

    it "round-trips a signed nil distinctly from an absent key" do
      # A nullable state key: its initialize default is a non-nil sentinel, so a
      # signed `nil` must override it (key presence, not value, decides restore).
      nullable_klass = Class.new do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "NullableThing"

        reactive_record :record
        reactive_state :filter

        def initialize(record:, filter: :unset)
          @record = record
          @filter = filter
        end

        attr_reader :filter

        def id = "nullable-#{@record.object_id}"
      end

      token = nullable_klass.new(record:, filter: nil).send(:reactive_token)
      rebuilt = nullable_klass.from_identity(Phlex::Reactive.verify(token))

      expect(rebuilt.filter).to be_nil # the signed nil wins, not the :unset default
    end

    it "the state cannot be tampered without breaking the signature" do
      token = record_state_klass.new(record:, attribute: :name, editing: false).send(:reactive_token)
      # Re-encode a payload that switches the editable column to "ssn" onto the
      # ORIGINAL signature — the signed digest no longer matches the data.
      data, sig = token.split("--", 2)
      decoded = JSON.parse(Base64.urlsafe_decode64(data))
      decoded["_rails"]["data"]["s"]["attribute"] = "ssn"
      forged = "#{Base64.urlsafe_encode64(decoded.to_json, padding: false)}--#{sig}"

      expect(Phlex::Reactive.verify(forged)).to be_nil
    end
  end

  describe "model_param_name unification (issue #4)" do
    # A record-backed component whose demodulized class name (`bar`) differs
    # from its reactive_record name (`baz`). The action endpoint builds it with
    # `reactive_record_key` (:baz); the broadcast path builds it via
    # `model_param_name`. Both MUST agree, or one path raises
    # `ArgumentError: missing keyword`.
    let(:record_klass) do
      Class.new do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "Foo::Bar"

        reactive_record :baz

        def initialize(baz:) = @baz = baz
        attr_reader :baz
        def id = "foo-bar-#{@baz.object_id}"
      end
    end

    it "broadcasts and clicks build with the same init keyword" do
      expect(record_klass.model_param_name).to eq(:baz)
    end

    it "build(model) constructs with reactive_record_key, not the class name" do
      record = Object.new
      built = record_klass.send(:build, record, {})
      expect(built.baz).to be(record)
    end

    it "falls back to the demodulized class name when no reactive_record is set" do
      state_backed = Class.new do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "Foo::Widget"

        reactive_state :count
        def initialize(count: 0) = @count = count
      end

      expect(state_backed.model_param_name).to eq(:widget)
    end

    it "falls back to the demodulized class name for Streamable-only components" do
      streamable_only = Class.new do
        include Phlex::Reactive::Streamable

        def self.name = "Foo::Row"

        def initialize(row:) = @row = row
      end

      expect(streamable_only.model_param_name).to eq(:row)
    end

    it "honors an explicit model_param_name override" do
      overridden = Class.new do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "Foo::Bar"
        def self.model_param_name = :explicit

        reactive_record :baz

        def initialize(explicit:) = @explicit = explicit
      end

      expect(overridden.model_param_name).to eq(:explicit)
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

  describe "#on trigger attributes (issue #17 debounce)" do
    subject(:instance) { state_klass.new }

    it "wires the action + event without a debounce by default" do
      attrs = instance.send(:on, :increment, event: "input")
      expect(attrs[:data][:action]).to eq("input->reactive#dispatch")
      expect(attrs[:data][:reactive_action_param]).to eq("increment")
      expect(attrs[:data]).not_to have_key(:reactive_debounce_param)
    end

    it "emits the debounce as a Stimulus param when given" do
      attrs = instance.send(:on, :set, event: "input", debounce: 300)
      expect(attrs[:data][:reactive_debounce_param]).to eq(300)
    end

    it "keeps debounce out of the explicit params payload" do
      attrs = instance.send(:on, :set, event: "input", debounce: 300, count: 5)
      expect(JSON.parse(attrs[:data][:reactive_params_param])).to eq({"count" => 5})
    end
  end
end
