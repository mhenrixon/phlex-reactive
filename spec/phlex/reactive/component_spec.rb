# frozen_string_literal: true

require "spec_helper"
require "phlex" # for the render-context-free `mix` helper used by reactive_root (issue #48)

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
      expect(payload["s"]).to eq({ "attribute" => "name", "editing" => true })
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
      # Mutate the signed DATA segment (left of the `--`) while keeping the
      # ORIGINAL signature — the HMAC over the data no longer matches, so verify
      # fails. Flipping a byte in the encoded payload is serializer-agnostic: it
      # works whether the verifier Marshals (the plain MessageVerifier in
      # spec_helper) or JSON-serializes (the app verifier under rails_helper),
      # unlike decoding+re-encoding a known payload shape.
      data, sig = token.split("--", 2)
      mutated = data.dup
      i = data.length / 2
      mutated[i] = (data[i] == "A" ? "B" : "A")
      forged = "#{mutated}--#{sig}"

      expect(forged).not_to eq(token) # sanity: we actually changed the data
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

  describe "#reactive_field param binding (issue #23)" do
    subject(:instance) { state_klass.new }

    it "binds the field name to the action param (drops the magic name: string)" do
      attrs = instance.send(:reactive_field, :count)
      expect(attrs[:name]).to eq("count")
    end

    it "merges extra attributes over the bound name" do
      attrs = instance.send(:reactive_field, :count, value: 7, data: { testid: "f" })
      expect(attrs[:name]).to eq("count")
      expect(attrs[:value]).to eq(7)
      expect(attrs[:data]).to eq({ testid: "f" })
    end

    it "lets an explicit name: override the param binding (escape hatch)" do
      attrs = instance.send(:reactive_field, :count, name: "other")
      expect(attrs[:name]).to eq("other")
    end
  end

  describe "#reactive_root (issue #48 — id on the root, not a child)" do
    subject(:instance) { root_klass.new }

    # A real Phlex component (so the render-context-free `mix` helper is present,
    # exactly as in production) with a custom #id. reactive_root must emit that id
    # ON the reactive-controller element, so this.element.id can never be empty and
    # #extractToken's first-token-wins fallback is unreachable.
    let(:root_klass) do
      Class.new(Phlex::HTML) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "RootThing"

        reactive_state :count
        def initialize(count: 0) = @count = count

        def id = "root-thing"
      end
    end

    it "spreads the component id ALONGSIDE reactive_attrs on one element" do
      attrs = instance.send(:reactive_root)
      expect(attrs[:id]).to eq("root-thing")
      expect(attrs[:data][:controller]).to eq("reactive")
      expect(attrs[:data][:reactive_token_value]).to be_a(String)
    end

    it "carries the SAME token reactive_attrs would (no second signing path)" do
      attrs = instance.send(:reactive_root)
      payload = Phlex::Reactive.verify(attrs[:data][:reactive_token_value])
      expect(payload["c"]).to eq("RootThing")
    end

    it "deep-merges overrides without clobbering the controller/token data:" do
      attrs = instance.send(:reactive_root, class: "card", data: { testid: "root" })
      expect(attrs[:class]).to eq("card")
      # the override's data: must NOT wipe out controller/reactive_token_value
      expect(attrs[:data][:controller]).to eq("reactive")
      expect(attrs[:data][:reactive_token_value]).to be_a(String)
      expect(attrs[:data][:testid]).to eq("root")
    end

    it "lets an explicit id: override win (escape hatch)" do
      attrs = instance.send(:reactive_root, id: "explicit")
      expect(attrs[:id]).to eq("explicit")
    end

    it "renders id and data-controller onto the SAME element (the whole point)" do
      render_klass = Class.new(root_klass) do
        def self.name = "RenderRootThing"
        def view_template = div(**reactive_root(class: "card")) { "hi" }
      end
      html = render_klass.new.call

      # the SAME opening tag carries BOTH the id and the controller — never split
      # across elements (the issue #48 footgun is `id:` on a child). Match the one
      # <div …> tag, then assert both attributes live inside it (order-independent).
      open_tag = html[/<div [^>]*>/]
      expect(open_tag).to include('id="root-thing"')
      expect(open_tag).to include('data-controller="reactive"')
      expect(open_tag).to include('class="card"')
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
      expect(JSON.parse(attrs[:data][:reactive_params_param])).to eq({ "count" => 5 })
    end

    # Performance: the no-params case (the common on(:increment)) must NOT
    # re-serialize an empty hash to JSON on every render — but the wire format
    # must stay exactly "{}" so the client's #parseParams is unaffected.
    it "emits an empty-object params payload (verbatim) with no explicit params" do
      attrs = instance.send(:on, :increment)
      expect(attrs[:data][:reactive_params_param]).to eq("{}")
    end

    it "still serializes explicit params" do
      attrs = instance.send(:on, :set, count: 9)
      expect(JSON.parse(attrs[:data][:reactive_params_param])).to eq({ "count" => 9 })
    end
  end

  describe "#on confirm gate (issue #52)" do
    subject(:instance) { state_klass.new }

    it "omits the confirm param by default" do
      attrs = instance.send(:on, :increment)
      expect(attrs[:data]).not_to have_key(:reactive_confirm_param)
    end

    it "emits the confirm message as a Stimulus param when given" do
      attrs = instance.send(:on, :destroy, confirm: "Really delete this item?")
      expect(attrs[:data][:reactive_confirm_param]).to eq("Really delete this item?")
    end

    it "keeps confirm out of the explicit params payload" do
      attrs = instance.send(:on, :set, confirm: "Sure?", count: 5)
      expect(JSON.parse(attrs[:data][:reactive_params_param])).to eq({ "count" => 5 })
    end

    it "threads confirm alongside debounce without collision" do
      attrs = instance.send(:on, :set, event: "input", debounce: 300, confirm: "Sure?")
      expect(attrs[:data][:reactive_debounce_param]).to eq(300)
      expect(attrs[:data][:reactive_confirm_param]).to eq("Sure?")
    end
  end

  # A record-backed component whose record is UNSAVED (new_record?) has no
  # GlobalID to sign. reactive_token must not crash calling to_gid on it — it
  # signs the declared state instead (the draft seed), so the client controller
  # still mounts and a client-side compute (reactive_compute) can drive the
  # unpersisted record in-browser. This is the "tokenless draft" seam.
  describe "record-backed component holding an UNSAVED record (draft seed)" do
    # A record double that is not persisted and raises on to_gid (mirroring
    # ActiveRecord::Base#to_gid on a new_record — MissingModelIdError).
    let(:unsaved_record) do
      Class.new do
        def persisted? = false
        def to_gid = raise(URI::GID::MissingModelIdError, "no id")
      end.new
    end

    let(:draft_klass) do
      Class.new do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "DraftThing"

        reactive_record :order
        reactive_state :total, :allowance

        def initialize(order:, total: 0, allowance: 0)
          @order = order
          @total = total
          @allowance = allowance
        end

        attr_reader :order, :total, :allowance

        def id = "draft-thing"
      end
    end

    it "signs {c, s} WITHOUT a gid when the record is unsaved (no crash)" do
      token = draft_klass.new(order: unsaved_record, total: 500, allowance: 100).send(:reactive_token)
      payload = Phlex::Reactive.verify(token)

      expect(payload["c"]).to eq("DraftThing")
      expect(payload).not_to have_key("gid")
      expect(payload["s"]).to eq({ "total" => 500, "allowance" => 100 })
    end

    it "still signs the gid when the record IS persisted" do
      saved = Struct.new(:gid_string).new("gid://app/Order/7")
      allow(saved).to receive_messages(persisted?: true, to_gid: instance_double(GlobalID, to_s: saved.gid_string))

      token = draft_klass.new(order: saved, total: 500).send(:reactive_token)
      payload = Phlex::Reactive.verify(token)

      expect(payload["gid"]).to eq("gid://app/Order/7")
    end
  end

  # reactive_compute declares a CLIENT-SIDE reducer: on `input`, the generic
  # controller runs a registered JS function over the named input fields and
  # writes the named output fields WITHOUT a round trip (the "instant" half of
  # the new-record UX), then the debounced POST reconciles from the server reply.
  # The Ruby side is pure hash-building — no view context, no DB — so it lives
  # here alongside on/reactive_field.
  describe "reactive_compute DSL (client-side data bindings)" do
    let(:compute_klass) do
      Class.new do
        include Phlex::Reactive::Component

        def self.name = "ComputeThing"

        reactive_state :total
        reactive_compute :payment_split,
          inputs: %i[allowance cash leasing total],
          outputs: %i[allowance cash leasing]

        def initialize(total: 0) = @total = total
      end
    end

    describe "declaration registry" do
      it "registers a declared compute" do
        expect(compute_klass.reactive_compute?(:payment_split)).to be(true)
      end

      it "does not register an undeclared name" do
        expect(compute_klass.reactive_compute?(:wat)).to be(false)
        expect(compute_klass.reactive_compute(:wat)).to be_nil
      end

      it "captures the inputs and outputs" do
        definition = compute_klass.reactive_compute(:payment_split)
        expect(definition.inputs).to eq(%i[allowance cash leasing total])
        expect(definition.outputs).to eq(%i[allowance cash leasing])
      end

      it "defaults the reducer key to the compute name" do
        expect(compute_klass.reactive_compute(:payment_split).reducer).to eq("payment_split")
      end

      it "honors an explicit reducer key" do
        klass = Class.new do
          include Phlex::Reactive::Component

          def self.name = "CustomReducer"
          reactive_compute :split, inputs: %i[a], outputs: %i[b], reducer: "shared_split"
        end
        expect(klass.reactive_compute(:split).reducer).to eq("shared_split")
      end
    end

    describe "inheritance" do
      it "inherits computes from a parent and adds its own without mutating the parent" do
        child = Class.new(compute_klass) do
          def self.name = "ComputeChild"
          reactive_compute :totals, inputs: %i[price qty], outputs: %i[total]
        end

        expect(child.reactive_compute?(:payment_split)).to be(true) # inherited
        expect(child.reactive_compute?(:totals)).to be(true)        # own
        expect(compute_klass.reactive_compute?(:totals)).to be(false) # parent unaffected
      end
    end

    describe "#reactive_compute_attrs (data attributes for the root)" do
      subject(:instance) { compute_klass.new }

      it "emits the reducer key and the input/output field names as data attrs" do
        attrs = instance.send(:reactive_compute_attrs, :payment_split)
        expect(attrs[:data][:reactive_compute_reducer_param]).to eq("payment_split")
        expect(JSON.parse(attrs[:data][:reactive_compute_inputs_param])).to eq(%w[allowance cash leasing total])
        expect(JSON.parse(attrs[:data][:reactive_compute_outputs_param])).to eq(%w[allowance cash leasing])
      end

      it "raises for an undeclared compute (fail fast, not a silent no-op)" do
        expect { instance.send(:reactive_compute_attrs, :nope) }
          .to raise_error(Phlex::Reactive::Error, /reactive_compute/)
      end
    end
  end

  # Performance: reactive_token runs on EVERY render. It must produce a byte-
  # identical payload before/after caching the ivar symbols + class name. These
  # pin the payload SHAPE (decoded) so an allocation optimization can't silently
  # change what's signed.
  describe "#reactive_token payload (perf invariants)" do
    it "signs {c, s} for a state-backed component, with string keys" do
      token = state_klass.new(count: 5).send(:reactive_token)
      expect(Phlex::Reactive.verify(token)).to eq("c" => "StateThing", "s" => { "count" => 5 })
    end

    it "is stable across repeated renders of equal state" do
      a = Phlex::Reactive.verify(state_klass.new(count: 3).send(:reactive_token))
      b = Phlex::Reactive.verify(state_klass.new(count: 3).send(:reactive_token))
      expect(a).to eq(b)
    end
  end
end
