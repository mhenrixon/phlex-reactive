# frozen_string_literal: true

require "spec_helper"
require "phlex" # for the render-context-free `mix` helper used by reactive_root (issue #48)

RSpec.describe Phlex::Reactive::Component do
  # A minimal state-backed component (no Rails/Phlex render needed for these).
  # It declares every action the #on specs exercise: on() now consults the
  # actions registry under verbose_errors (issue #105 — undeclared names raise at
  # render), which is ON whenever Rails is loaded (the combined fast suite), so a
  # trigger for an undeclared name would raise here. Declaring them keeps every
  # #on wire-format example green regardless of the flag's default.
  let(:state_klass) do
    Class.new do
      include Phlex::Reactive::Component

      def self.name = "StateThing"

      reactive_state :count
      action :increment
      action :set, params: { count: :integer }
      # Action names the #on option specs (debounce/listnav/confirm/keyboard/
      # modifiers/optimistic/loading) build triggers for — declared so the
      # render-time undeclared-action guard (issue #105) passes them through.
      %i[search destroy add cancel switch toggle track dismiss close_menu save].each { action(it) }

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

    it "compiles the param schema at declaration (issue #109)" do
      expect(state_klass.reactive_action(:set).schema).to be_a(Phlex::Reactive::ParamSchema)
    end

    it "raises UnknownParamType at CLASS LOAD for a typo'd type symbol (issue #109)" do
      expect do
        Class.new do
          include Phlex::Reactive::Component

          action :set, params: { count: :interger }
        end
      end.to raise_error(Phlex::Reactive::UnknownParamType, /interger/)
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

    it "ignores the token version key (#111) — the leftover \"v\" is harmless" do
      # verify leaves "v" in the payload; from_identity assembles kwargs only from
      # the declared record/state keys, so the version marker never reaches new(**).
      payload = Phlex::Reactive.verify(state_klass.new(count: 9).send(:reactive_token))
      expect(payload).to have_key("v")

      rebuilt = state_klass.from_identity(payload)
      expect(rebuilt.count).to eq(9) # rebuilt cleanly despite the extra "v"
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

  describe "#reactive_field dirty tracking (issue #103)" do
    # A real Phlex component so `mix` (Phlex::Helpers) is present, exactly as in
    # production — reactive_field(dirty:) deep-merges its trackDirty descriptor.
    subject(:instance) { field_klass.new }

    let(:field_klass) do
      Class.new(Phlex::HTML) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "DirtyFieldThing"

        reactive_state :count
        def initialize(count: 0) = @count = count
      end
    end

    it "wires the trackDirty action on dirty: true" do
      attrs = instance.send(:reactive_field, :title, dirty: true)
      expect(attrs[:name]).to eq("title")
      expect(attrs[:data][:action]).to eq("input->reactive#trackDirty")
    end

    it "does not consume dirty: as a literal HTML attribute" do
      attrs = instance.send(:reactive_field, :title, dirty: true)
      expect(attrs).not_to have_key(:dirty)
    end

    it "omits the trackDirty wiring when dirty is falsey (the default)" do
      expect(instance.send(:reactive_field, :title)).not_to have_key(:data)
      expect(instance.send(:reactive_field, :title, dirty: false)).not_to have_key(:data)
    end

    it "token-joins trackDirty onto a caller's own data-action instead of clobbering it" do
      # A field that also carries its own descriptor (mix deep-merges data-action).
      attrs = instance.send(:reactive_field, :title, dirty: true,
        data: { action: "blur->reactive#dispatch" })
      expect(attrs[:data][:action]).to eq("blur->reactive#dispatch input->reactive#trackDirty")
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

  describe "#reactive_root dirty tracking (issue #103)" do
    subject(:instance) { root_klass.new }

    let(:root_klass) do
      Class.new(Phlex::HTML) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "DirtyRootThing"

        reactive_state :count
        def initialize(count: 0) = @count = count

        def id = "dirty-root"
      end
    end

    it "mixes the trackDirty descriptor onto the root's data-action for track_dirty: true" do
      attrs = instance.send(:reactive_root, track_dirty: true)
      expect(attrs[:data][:action]).to eq("input->reactive#trackDirty")
      # still a full reactive root
      expect(attrs[:data][:controller]).to eq("reactive")
      expect(attrs[:id]).to eq("dirty-root")
    end

    it "does NOT emit track_dirty as a literal HTML attribute (kwarg consumed pre-mix)" do
      attrs = instance.send(:reactive_root, track_dirty: true)
      expect(attrs).not_to have_key(:track_dirty)
      expect(attrs.dig(:data, :track_dirty)).to be_nil
    end

    it "emits the warn-unsaved marker for warn_unsaved: true" do
      attrs = instance.send(:reactive_root, warn_unsaved: true)
      # STRING "true" (Phlex renders a boolean-true attr valueless → JS sees "" → falsy)
      expect(attrs[:data][:reactive_warn_unsaved]).to eq("true")
      expect(attrs).not_to have_key(:warn_unsaved)
    end

    it "does NOT emit warn_unsaved as a literal HTML attribute (kwarg consumed pre-mix)" do
      attrs = instance.send(:reactive_root, warn_unsaved: false)
      expect(attrs).not_to have_key(:warn_unsaved)
      expect(attrs.dig(:data, :reactive_warn_unsaved)).to be_nil
    end

    it "composes track_dirty with a caller's own data-action (token-join, not clobber)" do
      attrs = instance.send(:reactive_root, track_dirty: true,
        data: { action: "scroll->reactive#dispatch" })
      expect(attrs[:data][:action]).to eq("scroll->reactive#dispatch input->reactive#trackDirty")
      expect(attrs[:data][:controller]).to eq("reactive")
    end

    it "supports both flags at once, preserving id + controller + token" do
      attrs = instance.send(:reactive_root, track_dirty: true, warn_unsaved: true, class: "card")
      expect(attrs[:data][:action]).to eq("input->reactive#trackDirty")
      expect(attrs[:data][:reactive_warn_unsaved]).to eq("true")
      expect(attrs[:data][:controller]).to eq("reactive")
      expect(attrs[:data][:reactive_token_value]).to be_a(String)
      expect(attrs[:id]).to eq("dirty-root")
      expect(attrs[:class]).to eq("card")
    end

    it "renders no literal track-dirty/warn-unsaved attribute in the output" do
      render_klass = Class.new(root_klass) do
        def self.name = "RenderDirtyRoot"
        def view_template = div(**reactive_root(track_dirty: true, warn_unsaved: true)) { "hi" }
      end
      # NB: the trackDirty descriptor value contains a literal `>` (input->…), so a
      # /<div [^>]*>/ regex would truncate mid-attribute — assert on the whole tag.
      html = render_klass.new.call

      expect(html).to include('data-action="input->reactive#trackDirty"')
      expect(html).to include('data-reactive-warn-unsaved="true"')
      # the raw kwargs never leak through as attributes (no `track-dirty` /
      # `warn-unsaved` attribute, no `track_dirty`/`warn_unsaved` token anywhere)
      expect(html).not_to include("track-dirty")
      expect(html).not_to match(/\btrack_dirty\b/)
      expect(html).not_to match(/\bwarn_unsaved\b/)
    end
  end

  describe "#reactive_attrs debug flag (issue #108)" do
    subject(:instance) { state_klass.new }

    # This unit spec runs WITHOUT Rails, so debug defaults to false. Each example
    # sets it explicitly; restore the lazy default after each by removing the ivar
    # entirely so an explicit value never leaks into the next (the verbose_errors
    # precedent below).
    around do
      it.run
    ensure
      Phlex::Reactive.remove_instance_variable(:@debug) if Phlex::Reactive.instance_variable_defined?(:@debug)
    end

    it "omits data-reactive-debug when debug is off (the default)" do
      Phlex::Reactive.debug = false
      expect(instance.send(:reactive_attrs)[:data]).not_to have_key(:reactive_debug)
    end

    it "emits data-reactive-debug=\"true\" (STRING) when debug is on" do
      Phlex::Reactive.debug = true
      # STRING "true", not boolean: Phlex renders a boolean-true attr VALUELESS,
      # which the client's getAttribute reads as "" → falsy (the on()/warn_unsaved
      # precedent). The explicit ="true" is what the controller matches on.
      expect(instance.send(:reactive_attrs)[:data][:reactive_debug]).to eq("true")
    end

    it "flows the flag through reactive_root too" do
      Phlex::Reactive.debug = true
      attrs = instance.send(:reactive_attrs)
      expect(attrs[:data][:reactive_debug]).to eq("true")
      # still a full reactive root's attrs
      expect(attrs[:data][:controller]).to eq("reactive")
    end

    it "defaults debug to false with no Rails env" do
      Phlex::Reactive.remove_instance_variable(:@debug) if Phlex::Reactive.instance_variable_defined?(:@debug)
      expect(Phlex::Reactive.debug).to be(false)
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

  # Issue #105: on(:typo) — an undeclared action name (a typo, or an action you
  # forgot to declare) renders fine today and only surfaces as an unexplained
  # 403 at CLICK time (the endpoint's default-deny). With verbose_errors on
  # (dev + test), on() consults the actions registry and raises at RENDER time,
  # listing the declared actions — the same loud-failure precedent as
  # reactive_compute_attrs. Production (flag off) keeps today's permissive emit
  # so a stale page after a deploy that removed an action doesn't 500 on render.
  describe "#on undeclared-action guard (issue #105)" do
    subject(:instance) { state_klass.new }

    # This unit spec runs WITHOUT Rails (spec_helper), so verbose_errors defaults
    # to false — the raising path is flag-gated, so force it ON here (in a Rails
    # app it defaults ON in dev + test via Rails.env.local?). Restore the lazy
    # default after each example — remove the ivar entirely so the explicit value
    # never leaks into the next one.
    around do
      Phlex::Reactive.verbose_errors = true
      it.run
    ensure
      if Phlex::Reactive.instance_variable_defined?(:@verbose_errors)
        Phlex::Reactive.remove_instance_variable(:@verbose_errors)
      end
    end

    it "passes through for a declared action" do
      expect { instance.send(:on, :increment) }.not_to raise_error
      expect(instance.send(:on, :increment)[:data][:reactive_action_param]).to eq("increment")
    end

    it "raises for an undeclared action (a typo), naming it and listing the declared ones" do
      # (An anonymous test class stringifies as #<Class:0x…>, not its .name, so
      # we assert on the typo + the declared list — the parts a real component's
      # class name is embedded alongside.)
      expect { instance.send(:on, :incremnt) }
        .to raise_error(Phlex::Reactive::Error) {
          expect(it.message).to include("has no declared action :incremnt")
          expect(it.message).to include("declared: [").and include(":increment").and include(":set")
        }
    end

    it "does not raise when verbose_errors is off (production keeps the permissive emit)" do
      Phlex::Reactive.verbose_errors = false
      expect { instance.send(:on, :incremnt) }.not_to raise_error
      expect(instance.send(:on, :incremnt)[:data][:reactive_action_param]).to eq("incremnt")
    end

    it "runs the check BEFORE the debounce/throttle guard (a typo raises the action error first)" do
      # Both a typo AND the mutually-exclusive debounce+throttle are wrong; the
      # undeclared-action check is placed first, so it wins.
      expect { instance.send(:on, :incremnt, debounce: 100, throttle: 100) }
        .to raise_error(Phlex::Reactive::Error, /no declared action :incremnt/)
    end

    # A component that declares NO actions of its own is a cross-component
    # dispatch helper — a child row rendering a trigger for its CONTAINER's
    # action, sending the container's token (e.g. a notification row → the list's
    # :dismiss). It can't self-validate against a registry it doesn't own, so the
    # guard skips the empty case entirely rather than false-positive.
    it "skips the check for a component that declares no actions (cross-component dispatch)" do
      dispatch_helper = Class.new do
        include Phlex::Reactive::Component

        def self.name = "DispatchHelper"
      end
      instance = dispatch_helper.new

      expect { instance.send(:on, :dismiss, id: 7) }.not_to raise_error
      expect(instance.send(:on, :dismiss, id: 7)[:data][:reactive_action_param]).to eq("dismiss")
    end
  end

  describe "#on listnav (combobox keyboard navigation, issue #72)" do
    subject(:instance) { state_klass.new }

    it "appends the arrow/enter/escape listnav actions to the trigger's data-action" do
      attrs = instance.send(:on, :search, event: "input", debounce: 300, listnav: "[role=option]")
      expect(attrs[:data][:action]).to eq(
        "input->reactive#dispatch " \
        "keydown.down->reactive#listnavNext " \
        "keydown.up->reactive#listnavPrev " \
        "keydown.enter->reactive#listnavPick " \
        "keydown.esc->reactive#listnavClose"
      )
    end

    it "emits the option selector as a Stimulus param" do
      attrs = instance.send(:on, :search, event: "input", listnav: "[role=option]")
      expect(attrs[:data][:reactive_listnav_option_param]).to eq("[role=option]")
    end

    it "keeps listnav out of the explicit params payload" do
      attrs = instance.send(:on, :search, event: "input", listnav: "[role=option]", query: "x")
      expect(JSON.parse(attrs[:data][:reactive_params_param])).to eq({ "query" => "x" })
    end

    it "omits the listnav wiring entirely when not requested" do
      attrs = instance.send(:on, :search, event: "input")
      expect(attrs[:data][:action]).to eq("input->reactive#dispatch")
      expect(attrs[:data]).not_to have_key(:reactive_listnav_option_param)
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

  describe "#on keyboard filters via event: (Enter-to-submit / Escape-to-cancel)" do
    subject(:instance) { state_klass.new }

    it "passes a Stimulus keyboard-filter event through verbatim (Enter)" do
      attrs = instance.send(:on, :add, event: "keydown.enter")
      expect(attrs[:data][:action]).to eq("keydown.enter->reactive#dispatch")
    end

    it "passes an Escape filter through verbatim" do
      attrs = instance.send(:on, :cancel, event: "keydown.esc")
      expect(attrs[:data][:action]).to eq("keydown.esc->reactive#dispatch")
    end

    it "does not force type=button for a keyboard trigger (it's not a click)" do
      attrs = instance.send(:on, :add, event: "keydown.enter")
      expect(attrs).not_to have_key(:type)
    end

    it "threads a keyboard event alongside debounce and explicit params" do
      attrs = instance.send(:on, :add, event: "keydown.enter", debounce: 200, title: "x")
      expect(attrs[:data][:action]).to eq("keydown.enter->reactive#dispatch")
      expect(attrs[:data][:reactive_debounce_param]).to eq(200)
      expect(JSON.parse(attrs[:data][:reactive_params_param])).to eq({ "title" => "x" })
    end

    # Regression: `key` is an ordinary action-param name and MUST stay one (the
    # docs context switcher does on(:switch, key: opt[:key])). It is not a
    # reserved keyword — it rides in the params payload like any other.
    it "treats key: as a normal action param, not a keyboard filter" do
      attrs = instance.send(:on, :switch, key: "pgbus")
      expect(attrs[:data][:action]).to eq("click->reactive#dispatch")
      expect(JSON.parse(attrs[:data][:reactive_params_param])).to eq({ "key" => "pgbus" })
    end

    it "leaves the plain (non-keyboard) event descriptor untouched" do
      attrs = instance.send(:on, :toggle, event: "change")
      expect(attrs[:data][:action]).to eq("change->reactive#dispatch")
    end
  end

  describe "#on event modifiers (issue #80 — window:, once:, outside:, throttle:)" do
    subject(:instance) { state_klass.new }

    # The hot-path pin: a bare on(:x) — the overwhelmingly common trigger — must
    # emit EXACTLY today's hash. New modifiers may not perturb the no-modifier
    # descriptor, params payload, or the forced type="button" by a single byte.
    it "leaves the bare on(:x) emission byte-identical (no-modifier hot path)" do
      expect(instance.send(:on, :increment)).to eq(
        {
          data: {
            action: "click->reactive#dispatch",
            reactive_action_param: "increment",
            reactive_params_param: "{}"
          },
          type: "button"
        }
      )
    end

    it "window: true binds the descriptor to @window and flags the window param" do
      attrs = instance.send(:on, :track, window: true)
      expect(attrs[:data][:action]).to eq("click@window->reactive#dispatch")
      expect(attrs[:data][:reactive_window_param]).to eq("true")
    end

    it "window: true skips type=button (the trigger isn't an in-form button)" do
      attrs = instance.send(:on, :track, window: true)
      expect(attrs).not_to have_key(:type)
    end

    it "once: true appends Stimulus's :once option to the descriptor" do
      attrs = instance.send(:on, :dismiss, once: true)
      expect(attrs[:data][:action]).to eq("click->reactive#dispatch:once")
    end

    it "composes window: and once: in descriptor order (@window before :once)" do
      attrs = instance.send(:on, :dismiss, window: true, once: true)
      expect(attrs[:data][:action]).to eq("click@window->reactive#dispatch:once")
    end

    it "outside: true implies the window binding" do
      attrs = instance.send(:on, :close_menu, outside: true)
      expect(attrs[:data][:action]).to eq("click@window->reactive#dispatch")
      expect(attrs).not_to have_key(:type)
    end

    it "outside: true emits BOTH the outside and window Stimulus params" do
      attrs = instance.send(:on, :close_menu, outside: true)
      # The client decides preventDefault behavior from event.params (the window
      # flag), never by sniffing the descriptor — so outside must set both.
      expect(attrs[:data][:reactive_outside_param]).to eq("true")
      expect(attrs[:data][:reactive_window_param]).to eq("true")
    end

    it "throttle: emits the throttle window as a Stimulus param" do
      attrs = instance.send(:on, :track, event: "scroll", window: true, throttle: 250)
      expect(attrs[:data][:reactive_throttle_param]).to eq(250)
    end

    it "raises ArgumentError when both debounce: and throttle: are given" do
      expect { instance.send(:on, :track, debounce: 300, throttle: 250) }
        .to raise_error(ArgumentError, /debounce.*throttle/m)
    end

    it "keeps the modifiers out of the explicit params payload" do
      attrs = instance.send(:on, :close_menu, outside: true, once: true, throttle: 100, reason: "esc")
      expect(JSON.parse(attrs[:data][:reactive_params_param])).to eq({ "reason" => "esc" })
    end

    it "omits every modifier param by default" do
      attrs = instance.send(:on, :increment)
      expect(attrs[:data]).not_to have_key(:reactive_window_param)
      expect(attrs[:data]).not_to have_key(:reactive_outside_param)
      expect(attrs[:data]).not_to have_key(:reactive_throttle_param)
    end
  end

  describe "#on optimistic hints (issue #98 — declared, reversible visual hints)" do
    subject(:instance) { state_klass.new }

    it "omits the optimistic param by default (bare on() hot path untouched)" do
      attrs = instance.send(:on, :increment)
      expect(attrs[:data]).not_to have_key(:reactive_optimistic_param)
    end

    it "emits the optimistic hint hash as a JSON Stimulus param" do
      attrs = instance.send(:on, :toggle, optimistic: { checked: :keep })
      expect(JSON.parse(attrs[:data][:reactive_optimistic_param])).to eq({ "checked" => "keep" })
    end

    it "serializes a class op with a single class string" do
      attrs = instance.send(:on, :toggle, optimistic: { toggle_class: "done" })
      expect(JSON.parse(attrs[:data][:reactive_optimistic_param])).to eq({ "toggle_class" => ["done"] })
    end

    it "serializes a class op with an array of classes" do
      attrs = instance.send(:on, :toggle, optimistic: { add_class: %w[busy dim] })
      expect(JSON.parse(attrs[:data][:reactive_optimistic_param])).to eq({ "add_class" => %w[busy dim] })
    end

    it "serializes remove_class" do
      attrs = instance.send(:on, :toggle, optimistic: { remove_class: "active" })
      expect(JSON.parse(attrs[:data][:reactive_optimistic_param])).to eq({ "remove_class" => ["active"] })
    end

    it "serializes hide: true" do
      attrs = instance.send(:on, :destroy, optimistic: { hide: true })
      expect(JSON.parse(attrs[:data][:reactive_optimistic_param])).to eq({ "hide" => true })
    end

    it "normalizes to: :root to the @root sentinel" do
      attrs = instance.send(:on, :destroy, optimistic: { hide: true, to: :root })
      expect(JSON.parse(attrs[:data][:reactive_optimistic_param])).to eq({ "hide" => true, "to" => "@root" })
    end

    it "passes a to: CSS selector string through verbatim" do
      attrs = instance.send(:on, :toggle, optimistic: { add_class: "on", to: ".badge" })
      expect(JSON.parse(attrs[:data][:reactive_optimistic_param])).to eq({ "add_class" => ["on"], "to" => ".badge" })
    end

    it "combines several hint ops in one hash (checked + class)" do
      attrs = instance.send(:on, :toggle, event: "change", optimistic: { checked: :keep, toggle_class: "done" })
      expect(JSON.parse(attrs[:data][:reactive_optimistic_param]))
        .to eq({ "checked" => "keep", "toggle_class" => ["done"] })
    end

    it "keeps the optimistic hint out of the explicit params payload" do
      attrs = instance.send(:on, :toggle, optimistic: { hide: true }, reason: "gone")
      expect(JSON.parse(attrs[:data][:reactive_params_param])).to eq({ "reason" => "gone" })
    end

    it "threads optimistic alongside confirm and debounce without collision" do
      attrs = instance.send(:on, :destroy, confirm: "Sure?", debounce: 200, optimistic: { hide: true })
      expect(attrs[:data][:reactive_confirm_param]).to eq("Sure?")
      expect(attrs[:data][:reactive_debounce_param]).to eq(200)
      expect(JSON.parse(attrs[:data][:reactive_optimistic_param])).to eq({ "hide" => true })
    end

    it "rejects an unknown hint op (default-deny — a dead hint must fail at build)" do
      expect { instance.send(:on, :toggle, optimistic: { explode: true }) }
        .to raise_error(ArgumentError, /explode/)
    end

    it "rejects a checked: value other than :keep" do
      expect { instance.send(:on, :toggle, optimistic: { checked: :flip }) }
        .to raise_error(ArgumentError, /checked/)
    end

    it "rejects a non-hash optimistic:" do
      expect { instance.send(:on, :toggle, optimistic: [%w[toggle_class done]]) }
        .to raise_error(ArgumentError, /optimistic/)
    end

    # checked: :keep on a click trigger must NOT force type="button" — the hint's
    # whole point is a native checkbox/radio flip, and a forced button type would
    # destroy the control (issue #98). The caller supplies the real type.
    it "skips the forced type=button for a click trigger with checked: :keep" do
      attrs = instance.send(:on, :toggle, optimistic: { checked: :keep })
      expect(attrs).not_to have_key(:type)
    end

    it "still forces type=button for a click trigger whose hint is NOT checked: :keep" do
      attrs = instance.send(:on, :destroy, optimistic: { hide: true })
      expect(attrs[:type]).to eq("button")
    end

    it "still forces type=button for a bare click trigger (no optimistic hint)" do
      attrs = instance.send(:on, :increment)
      expect(attrs[:type]).to eq("button")
    end
  end

  describe "#on loading states (issue #99 — loading:/disable_with:)" do
    subject(:instance) { state_klass.new }

    it "omits the loading param by default (bare on() hot path untouched)" do
      attrs = instance.send(:on, :increment)
      expect(attrs[:data]).not_to have_key(:reactive_loading_param)
    end

    it "expands disable_with: shorthand to { disable: true, text: … }" do
      attrs = instance.send(:on, :save, disable_with: "Saving…")
      expect(JSON.parse(attrs[:data][:reactive_loading_param]))
        .to eq({ "disable" => true, "text" => "Saving…" })
    end

    it "emits a full loading: hash (disable + class + text)" do
      attrs = instance.send(:on, :save, loading: { disable: true, class: "opacity-50", text: "Saving…" })
      expect(JSON.parse(attrs[:data][:reactive_loading_param]))
        .to eq({ "disable" => true, "class" => ["opacity-50"], "text" => "Saving…" })
    end

    it "serializes a loading class array" do
      attrs = instance.send(:on, :save, loading: { class: %w[opacity-50 pointer-events-none] })
      expect(JSON.parse(attrs[:data][:reactive_loading_param]))
        .to eq({ "class" => %w[opacity-50 pointer-events-none] })
    end

    it "normalizes loading disable: to a real boolean" do
      attrs = instance.send(:on, :save, loading: { disable: true })
      expect(JSON.parse(attrs[:data][:reactive_loading_param])).to eq({ "disable" => true })
    end

    it "normalizes to: :root to the @root sentinel" do
      attrs = instance.send(:on, :save, loading: { class: "busy", to: :root })
      expect(JSON.parse(attrs[:data][:reactive_loading_param]))
        .to eq({ "class" => ["busy"], "to" => "@root" })
    end

    it "passes a to: CSS selector string through verbatim" do
      attrs = instance.send(:on, :save, loading: { class: "busy", to: ".spinner" })
      expect(JSON.parse(attrs[:data][:reactive_loading_param]))
        .to eq({ "class" => ["busy"], "to" => ".spinner" })
    end

    it "merges disable_with: over loading: (disable_with wins on text + implies disable)" do
      attrs = instance.send(:on, :save, loading: { class: "busy" }, disable_with: "Saving…")
      expect(JSON.parse(attrs[:data][:reactive_loading_param]))
        .to eq({ "class" => ["busy"], "disable" => true, "text" => "Saving…" })
    end

    it "keeps the loading hint out of the explicit params payload" do
      attrs = instance.send(:on, :save, disable_with: "Saving…", reason: "click")
      expect(JSON.parse(attrs[:data][:reactive_params_param])).to eq({ "reason" => "click" })
    end

    it "threads loading alongside confirm, debounce and optimistic without collision" do
      attrs = instance.send(:on, :save, confirm: "Sure?", debounce: 200,
        optimistic: { add_class: "pending" }, disable_with: "Saving…")
      expect(attrs[:data][:reactive_confirm_param]).to eq("Sure?")
      expect(attrs[:data][:reactive_debounce_param]).to eq(200)
      expect(JSON.parse(attrs[:data][:reactive_optimistic_param])).to eq({ "add_class" => ["pending"] })
      expect(JSON.parse(attrs[:data][:reactive_loading_param]))
        .to eq({ "disable" => true, "text" => "Saving…" })
    end

    it "rejects an unknown loading key (default-deny — a dead hint fails at build)" do
      expect { instance.send(:on, :save, loading: { spin: true }) }
        .to raise_error(ArgumentError, /spin/)
    end

    it "rejects a non-hash loading:" do
      expect { instance.send(:on, :save, loading: "Saving…") }
        .to raise_error(ArgumentError, /loading/)
    end

    it "still forces type=button for a click trigger with a loading hint" do
      attrs = instance.send(:on, :save, disable_with: "Saving…")
      expect(attrs[:type]).to eq("button")
    end
  end

  describe "#busy_on (issue #99 — scoped busy indicators)" do
    subject(:instance) { state_klass.new }

    it "emits data-reactive-busy-on for the named action" do
      expect(instance.send(:busy_on, :save)).to eq({ data: { reactive_busy_on: "save" } })
    end

    it "stringifies a symbol action name" do
      expect(instance.send(:busy_on, :destroy)[:data][:reactive_busy_on]).to eq("destroy")
    end

    it "accepts a string action name" do
      expect(instance.send(:busy_on, "save")[:data][:reactive_busy_on]).to eq("save")
    end
  end

  describe "#on_client (issue #95 — client-only DOM ops, zero round trip)" do
    subject(:instance) { state_klass.new }

    let(:ops) { instance.js.toggle("#menu") }

    it "exposes the js builder as an instance helper" do
      expect(instance.js).to be_a(Phlex::Reactive::JS)
    end

    it "binds the event to runOps and carries ONLY the ops (no token, no action, no params)" do
      attrs = instance.send(:on_client, :click, ops)

      expect(attrs[:data][:action]).to eq("click->reactive#runOps")
      expect(attrs[:data][:reactive_ops_param]).to eq('[["toggle",{"to":"#menu"}]]')
      expect(attrs[:data]).not_to have_key(:reactive_action_param)
      expect(attrs[:data]).not_to have_key(:reactive_params_param)
      expect(attrs[:data]).not_to have_key(:reactive_token_value)
    end

    it "forces type=button for click triggers (a bare button in a form must not submit)" do
      expect(instance.send(:on_client, :click, ops)[:type]).to eq("button")
    end

    it "composes window:/once: into the descriptor and skips type=button when window-bound" do
      attrs = instance.send(:on_client, :click, ops, window: true, once: true)

      expect(attrs[:data][:action]).to eq("click@window->reactive#runOps:once")
      expect(attrs[:data][:reactive_window_param]).to eq("true")
      expect(attrs).not_to have_key(:type)
    end

    it "outside: implies the window binding and emits BOTH flags as string params" do
      attrs = instance.send(:on_client, :click, ops, outside: true)

      expect(attrs[:data][:action]).to eq("click@window->reactive#runOps")
      expect(attrs[:data][:reactive_outside_param]).to eq("true")
      expect(attrs[:data][:reactive_window_param]).to eq("true")
    end

    it "rejects anything that is not a Phlex::Reactive::JS chain" do
      expect { instance.send(:on_client, :click, [["toggle", { "to" => "#menu" }]]) }
        .to raise_error(ArgumentError, /Phlex::Reactive::JS/)
    end

    it "rejects an empty op chain (a dead trigger must fail loudly at render)" do
      expect { instance.send(:on_client, :click, instance.js) }
        .to raise_error(ArgumentError, /no ops/)
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

    it "signs {c, s} WITHOUT a gid when the record ivar is nil (no nil.to_gid crash)" do
      # A record-backed component constructed with no record: the ivar guard
      # must short-circuit before to_gid so the token still signs the state.
      token = draft_klass.new(order: nil, total: 500, allowance: 100).send(:reactive_token)
      payload = Phlex::Reactive.verify(token)

      expect(payload).not_to have_key("gid")
      expect(payload["s"]).to eq({ "total" => 500, "allowance" => 100 })
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

    # Issue #104: typed inputs. The ARRAY form must stay byte-identical on the
    # wire (a JSON ARRAY, numeric coercion on the client). The HASH form declares
    # a per-input type and emits a JSON OBJECT ({"title":"string","qty":"number"})
    # so the client reads a :string input raw and coerces a :number through Number.
    describe "typed inputs (issue #104)" do
      let(:typed_klass) do
        Class.new do
          include Phlex::Reactive::Component

          def self.name = "TypedCompute"

          reactive_compute :preview,
            inputs: { title: :string, qty: :number },
            outputs: %i[title_preview char_count]
        end
      end

      it "keeps the ARRAY form's inputs param a byte-identical JSON array" do
        # The exact serialized string the client parses — pinned so the typed-
        # inputs change can never silently alter the shipped array-form wire.
        attrs = compute_klass.new.send(:reactive_compute_attrs, :payment_split)
        expect(attrs[:data][:reactive_compute_inputs_param])
          .to eq('["allowance","cash","leasing","total"]')
      end

      it "captures the input names in declaration order" do
        expect(typed_klass.reactive_compute(:preview).inputs).to eq(%i[title qty])
      end

      it "captures the per-input types keyed by name" do
        expect(typed_klass.reactive_compute(:preview).input_types)
          .to eq(title: :string, qty: :number)
      end

      it "reports nil input_types for the array form (untyped, numeric)" do
        expect(compute_klass.reactive_compute(:payment_split).input_types).to be_nil
      end

      it "emits the HASH form's inputs param as a JSON object of name→type" do
        attrs = typed_klass.new.send(:reactive_compute_attrs, :preview)
        expect(JSON.parse(attrs[:data][:reactive_compute_inputs_param]))
          .to eq("title" => "string", "qty" => "number")
      end

      it "still emits the outputs param as a JSON array for the hash form" do
        attrs = typed_klass.new.send(:reactive_compute_attrs, :preview)
        expect(JSON.parse(attrs[:data][:reactive_compute_outputs_param]))
          .to eq(%w[title_preview char_count])
      end
    end

    # Issue #159: cross-root text mirrors. `mirror:` declares an ALLOWLISTED map
    # from a compute name to document-wide id selector(s) painted via textContent
    # — the declared escape from root isolation (issue #15) for a derived value
    # shown in a recap OUTSIDE the computing root. Id selectors only (two-sided
    # default-deny with the client interpreter); the wire is byte-identical when
    # no mirror is declared.
    describe "cross-root mirrors (mirror:, issue #159)" do
      let(:mirror_klass) do
        Class.new do
          include Phlex::Reactive::Component

          def self.name = "MirrorCompute"

          reactive_compute :split,
            inputs: %i[a b total],
            outputs: %i[a b],
            mirror: { sum_a: "#sum_a", sum_total: ["#sum_total", "#footer-total"] }
        end
      end

      it "captures the mirror map normalized to name → array of id selectors" do
        expect(mirror_klass.reactive_compute(:split).mirror)
          .to eq(sum_a: ["#sum_a"], sum_total: ["#sum_total", "#footer-total"])
      end

      it "reports nil mirror when undeclared" do
        expect(compute_klass.reactive_compute(:payment_split).mirror).to be_nil
      end

      it "rejects mirror: on the bare GETTER form LOUDLY (never silently drops it)" do
        expect do
          Class.new do
            include Phlex::Reactive::Component

            def self.name = "MirrorOnly"
            reactive_compute :split, mirror: { sum: "#sum" }
          end
        end.to raise_error(ArgumentError, /mirror:.*inputs/m)
      end

      it "rejects a non-id selector LOUDLY at declare time (class, attribute, *, compound)" do
        # rubocop:disable Style/ItBlockParameter -- `bad` is read inside the nested Class.new block, where `it` would rebind
        [".totals", "[data-x]", "*", "div#x", "#x .y", "#x,#y"].each do |bad|
          expect do
            Class.new do
              include Phlex::Reactive::Component

              def self.name = "BadMirror"
              reactive_compute :split, inputs: %i[a], outputs: %i[b], mirror: { sum: bad }
            end
          end.to raise_error(ArgumentError, /id selector/i), "expected #{bad.inspect} to be refused"
        end
        # rubocop:enable Style/ItBlockParameter
      end

      it "emits the mirror map as a JSON object of name → [ids] on the root attrs" do
        attrs = mirror_klass.new.send(:reactive_compute_attrs, :split)
        expect(JSON.parse(attrs[:data][:reactive_compute_mirror_param]))
          .to eq("sum_a" => ["#sum_a"], "sum_total" => ["#sum_total", "#footer-total"])
      end

      it "emits NO mirror param when undeclared (the wire stays byte-identical)" do
        attrs = compute_klass.new.send(:reactive_compute_attrs, :payment_split)
        expect(attrs[:data]).not_to have_key(:reactive_compute_mirror_param)
      end
    end
  end

  # Issue #104: reactive_text mirrors a field into a TEXT NODE (live preview,
  # char counter, "Hello, {name}") — the text sibling of reactive_field. It
  # carries NO `name` attribute, so #collectFields never sweeps it into params.
  describe "#reactive_text (text-node mirror, issue #104)" do
    let(:text_klass) do
      Class.new(Phlex::HTML) do
        include Phlex::Reactive::Component

        def self.name = "TextMirror"

        def view_template
          reactive_text(:title_preview, "Hello")
        end
      end
    end

    let(:empty_klass) do
      Class.new(Phlex::HTML) do
        include Phlex::Reactive::Component

        def self.name = "EmptyTextMirror"

        def view_template
          reactive_text(:char_count)
        end
      end
    end

    it "renders a span carrying data-reactive-text=<name> with the initial content" do
      html = text_klass.new.call
      expect(html).to include('data-reactive-text="title_preview"')
      expect(html).to include(">Hello</span>")
    end

    it "renders an empty span when no initial value is given" do
      html = empty_klass.new.call
      expect(html).to include('data-reactive-text="char_count"')
      expect(html).to match(%r{<span[^>]*data-reactive-text="char_count"[^>]*></span>})
    end

    it "carries NO name attribute (so it is never collected/POSTed as a param)" do
      expect(text_klass.new.call).not_to include("name=")
    end
  end

  # Issue #161: reactive_show — value-conditional visibility (the x-show /
  # data-show equivalent). The TARGET element declares which owned field
  # controls it plus ONE literal predicate; the client toggles `hidden` from
  # the field's current value with no round trip. The predicate is a declared
  # literal match (equals:/not:/in:) — never an expression — so there is no
  # eval surface, and validation is loud at render time (exactly one predicate,
  # a non-empty in: list).
  describe "#reactive_show (value-conditional visibility, issue #161)" do
    subject(:instance) { show_klass.new }

    let(:show_klass) do
      Class.new(Phlex::HTML) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "ShowThing"

        reactive_state :count
        def initialize(count: 0) = @count = count
      end
    end

    it "emits the field binding and the equals: predicate" do
      attrs = instance.send(:reactive_show, :kind, equals: "premium")
      expect(attrs[:data][:reactive_show_field]).to eq("kind")
      expect(attrs[:data][:reactive_show_equals]).to eq("premium")
    end

    it "emits the not: predicate" do
      attrs = instance.send(:reactive_show, :mode, not: "off")
      expect(attrs[:data][:reactive_show_field]).to eq("mode")
      expect(attrs[:data][:reactive_show_not]).to eq("off")
    end

    it "emits the in: predicate as a JSON array of strings" do
      attrs = instance.send(:reactive_show, :size, in: [:l, "xl"])
      expect(attrs[:data][:reactive_show_in]).to eq(%w[l xl].to_json)
    end

    it "stringifies a boolean equals: so a checkbox binding reads naturally" do
      # A checkbox's .value is the constant "on"; the client compares its
      # checked state as "true"/"false" — so equals: true is the checkbox form.
      attrs = instance.send(:reactive_show, :gift, equals: true)
      expect(attrs[:data][:reactive_show_equals]).to eq("true")
    end

    it "stringifies symbols and numbers in every predicate position" do
      expect(instance.send(:reactive_show, :kind, equals: :premium)[:data][:reactive_show_equals])
        .to eq("premium")
      expect(instance.send(:reactive_show, :qty, not: 0)[:data][:reactive_show_not]).to eq("0")
      expect(instance.send(:reactive_show, :size, in: [1, 2])[:data][:reactive_show_in])
        .to eq(%w[1 2].to_json)
    end

    it "treats equals: nil as the empty string (visible while the field is blank)" do
      attrs = instance.send(:reactive_show, :note, equals: nil)
      expect(attrs[:data][:reactive_show_equals]).to eq("")
    end

    it "deep-merges extra attributes without clobbering the binding data" do
      attrs = instance.send(:reactive_show, :kind, equals: "premium",
        class: "panel", data: { testid: "p" })
      expect(attrs[:class]).to eq("panel")
      expect(attrs[:data][:testid]).to eq("p")
      expect(attrs[:data][:reactive_show_field]).to eq("kind")
      expect(attrs[:data][:reactive_show_equals]).to eq("premium")
    end

    it "raises without a predicate (a dead binding must fail at render)" do
      expect { instance.send(:reactive_show, :kind) }
        .to raise_error(ArgumentError, /exactly one predicate/)
    end

    it "raises with more than one predicate (ambiguous match)" do
      expect { instance.send(:reactive_show, :kind, equals: "a", not: "b") }
        .to raise_error(ArgumentError, /exactly one predicate/)
    end

    it "raises on an empty in: list (matches nothing — a dead binding)" do
      expect { instance.send(:reactive_show, :size, in: []) }
        .to raise_error(ArgumentError, /in: needs at least one value/)
    end

    it "renders the wire attributes onto the element" do
      klass = Class.new(Phlex::HTML) do
        include Phlex::Reactive::Component

        def self.name = "ShowRender"

        def view_template
          div(**reactive_show(:mode, not: "off"), id: "details") { "d" }
        end
      end

      html = klass.new.call
      expect(html).to include('data-reactive-show-field="mode"')
      expect(html).to include('data-reactive-show-not="off"')
    end
  end

  # Issue #163: reactive_filter — client-side option filtering for the
  # searchable combobox. The ROOT declares which input drives the filter and
  # which elements are the options (plus optional group/empty selectors); the
  # client shows/hides options by their data-reactive-filter-text haystack on
  # every input — no round trip, no bespoke per-feature controller. Validation
  # is loud at render time: blank selectors are dead bindings.
  describe "#reactive_filter (client-side option filtering, issue #163)" do
    subject(:instance) { filter_klass.new }

    let(:filter_klass) do
      Class.new(Phlex::HTML) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "FilterThing"
      end
    end

    it "emits the input and option selectors as root data attributes" do
      attrs = instance.send(:reactive_filter, input: "#search", option: "[role=option]")
      expect(attrs[:data][:reactive_filter_input]).to eq("#search")
      expect(attrs[:data][:reactive_filter_option]).to eq("[role=option]")
    end

    it "omits group/empty entirely when not given (byte-stable wire)" do
      attrs = instance.send(:reactive_filter, input: "#search", option: "[role=option]")
      expect(attrs[:data]).not_to have_key(:reactive_filter_group)
      expect(attrs[:data]).not_to have_key(:reactive_filter_empty)
    end

    it "emits the optional group and empty selectors when given" do
      attrs = instance.send(:reactive_filter,
        input: "#search", option: "[role=option]",
        group: "[data-filter-group]", empty: "#no-matches")
      expect(attrs[:data][:reactive_filter_group]).to eq("[data-filter-group]")
      expect(attrs[:data][:reactive_filter_empty]).to eq("#no-matches")
    end

    it "raises on a blank input selector (a dead binding must fail at render)" do
      expect { instance.send(:reactive_filter, input: "", option: "[role=option]") }
        .to raise_error(ArgumentError, /input:/)
    end

    it "raises on a blank option selector" do
      expect { instance.send(:reactive_filter, input: "#search", option: " ") }
        .to raise_error(ArgumentError, /option:/)
    end

    it "raises on an explicitly blank group/empty selector" do
      expect { instance.send(:reactive_filter, input: "#s", option: "[role=option]", group: "") }
        .to raise_error(ArgumentError, /group:/)
      expect { instance.send(:reactive_filter, input: "#s", option: "[role=option]", empty: "") }
        .to raise_error(ArgumentError, /empty:/)
    end

    it "renders the wire attributes onto the root element" do
      klass = Class.new(Phlex::HTML) do
        include Phlex::Reactive::Component

        def self.name = "FilterRender"

        def view_template
          div(**reactive_filter(input: "#search", option: "[role=option]", empty: "#none"), id: "combo") { "c" }
        end
      end

      html = klass.new.call
      expect(html).to include('data-reactive-filter-input="#search"')
      expect(html).to include('data-reactive-filter-option="[role=option]"')
      expect(html).to include('data-reactive-filter-empty="#none"')
    end
  end

  # Issue #163 (the compose half): reactive_listnav — the STANDALONE keyboard-nav
  # wiring for an input that fires no action. on(..., listnav:) requires a
  # declared action (a POST per keystroke); a preload-and-filter combobox input
  # is pure client, so it needs the same Arrow/Enter/Escape wiring without the
  # dispatch descriptor.
  describe "#reactive_listnav (standalone keyboard nav, issue #163)" do
    subject(:instance) { state_klass.new }

    it "emits ONLY the listnav keyboard actions (no dispatch — no POST)" do
      attrs = instance.send(:reactive_listnav, "[role=option]")
      expect(attrs[:data][:action]).to eq(
        "keydown.down->reactive#listnavNext " \
        "keydown.up->reactive#listnavPrev " \
        "keydown.enter->reactive#listnavPick " \
        "keydown.esc->reactive#listnavClose"
      )
      expect(attrs[:data][:action]).not_to include("reactive#dispatch")
    end

    it "emits the option selector as the same Stimulus param on() uses" do
      attrs = instance.send(:reactive_listnav, "[role=option]")
      expect(attrs[:data][:reactive_listnav_option_param]).to eq("[role=option]")
    end

    it "raises on a blank selector (a dead binding must fail at render)" do
      expect { instance.send(:reactive_listnav, "") }.to raise_error(ArgumentError, /selector/)
    end

    it "deep-merges with extra attrs via mix (data-action survives)" do
      # mix is Phlex::HTML's (render-context-free) helper, so this example needs
      # a Phlex-based component — state_klass is a plain class.
      phlex_instance = Class.new(Phlex::HTML) do
        include Phlex::Reactive::Component

        def self.name = "ListnavMix"
      end.new

      attrs = phlex_instance.instance_eval do
        mix(reactive_listnav("[role=option]"), data: { testid: "q" })
      end
      expect(attrs[:data][:action]).to include("reactive#listnavNext")
      expect(attrs[:data][:testid]).to eq("q")
    end
  end

  # Performance: reactive_token runs on EVERY render. It must produce a byte-
  # identical payload before/after caching the ivar symbols + class name. These
  # pin the payload SHAPE (decoded) so an allocation optimization can't silently
  # change what's signed.
  describe "#reactive_token payload (perf invariants)" do
    it "signs {c, s} for a state-backed component, with string keys (+ version marker #111)" do
      token = state_klass.new(count: 5).send(:reactive_token)
      expect(Phlex::Reactive.verify(token))
        .to eq("c" => "StateThing", "s" => { "count" => 5 }, "v" => Phlex::Reactive::TOKEN_VERSION)
    end

    it "is stable across repeated renders of equal state" do
      a = Phlex::Reactive.verify(state_klass.new(count: 3).send(:reactive_token))
      b = Phlex::Reactive.verify(state_klass.new(count: 3).send(:reactive_token))
      expect(a).to eq(b)
    end
  end
end
