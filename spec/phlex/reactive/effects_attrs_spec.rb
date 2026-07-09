# frozen_string_literal: true

require "spec_helper"
require "phlex"

# Issue #215: the reactive_effects class declaration and the root-attr
# emission. The RESOLVED effects (global ⊕ component, most specific wins)
# ride the component root as data-reactive-effect-<hook> attributes — the
# client's stream interceptor reads them off the target/incoming element.
# Off (the default) emits NOTHING: the wire stays byte-identical.
RSpec.describe Phlex::Reactive::Effects, "reactive_effects DSL + root attrs" do
  after do
    Phlex::Reactive.effects = nil
  end

  def component_class(&block)
    Class.new(Phlex::HTML) do
      include Phlex::Reactive::ClientBindings

      def self.name = "EffectsSpecComponent"

      class_eval(&block) if block

      def view_template
        div(**reactive_root) { "x" }
      end
    end
  end

  def effect_data(klass)
    klass.new.send(:reactive_attrs)[:data]
  end

  describe "off by default (byte-stable wire)" do
    it "emits no effect attrs with no config and no declaration" do
      expect(effect_data(component_class).keys.grep(/reactive_effect/)).to be_empty
    end
  end

  describe "global opt-in" do
    it "stamps every component root with the global set" do
      Phlex::Reactive.effects = true
      data = effect_data(component_class)
      expect(data[:reactive_effect_enter]).to eq("fade")
      expect(data[:reactive_effect_exit]).to eq("fade")
      expect(data[:reactive_effect_update]).to eq("highlight")
    end

    it "renders as data-reactive-effect-* attributes end to end" do
      Phlex::Reactive.effects = { enter: :slide }
      html = component_class.new.call
      expect(html).to include('data-reactive-effect-enter="slide"')
    end
  end

  describe "component-level declaration" do
    it "works standalone — declaring on a component IS that component's opt-in" do
      klass = component_class { reactive_effects enter: :scale }
      data = effect_data(klass)
      expect(data[:reactive_effect_enter]).to eq("scale")
      expect(data).not_to have_key(:reactive_effect_exit)
    end

    it "refines the global set per hook (most specific wins)" do
      Phlex::Reactive.effects = true
      klass = component_class { reactive_effects enter: :slide }
      data = effect_data(klass)
      expect(data[:reactive_effect_enter]).to eq("slide")
      expect(data[:reactive_effect_exit]).to eq("fade")
      expect(data[:reactive_effect_update]).to eq("highlight")
    end

    it "disables one hook with false while keeping the global rest" do
      Phlex::Reactive.effects = true
      klass = component_class { reactive_effects update: false }
      data = effect_data(klass)
      expect(data).not_to have_key(:reactive_effect_update)
      expect(data[:reactive_effect_enter]).to eq("fade")
    end

    it "opts the component out entirely with reactive_effects false" do
      Phlex::Reactive.effects = true
      klass = component_class { reactive_effects false }
      expect(effect_data(klass).keys.grep(/reactive_effect/)).to be_empty
    end

    it "rejects reactive_effects false combined with hooks" do
      expect { component_class { reactive_effects false, enter: :fade } }
        .to raise_error(ArgumentError, /false/)
    end

    it "rejects a bare no-argument call (declare hooks or false)" do
      expect { component_class { reactive_effects } }
        .to raise_error(ArgumentError, /enter/)
    end

    it "rejects an unknown effect name at declaration time (class load, not click time)" do
      expect { component_class { reactive_effects enter: :sparkle } }
        .to raise_error(ArgumentError, /sparkle/)
    end

    it "compiles named legs to the wire JSON on the root attr" do
      klass = component_class do
        reactive_effects enter: { during: "transition-all", from: "opacity-0", to: "opacity-100" }
      end
      expect(effect_data(klass)[:reactive_effect_enter])
        .to eq(%(["transition-all","opacity-0","opacity-100"]))
    end

    it "allows :random" do
      klass = component_class { reactive_effects update: :random }
      expect(effect_data(klass)[:reactive_effect_update]).to eq("random")
    end
  end

  describe "inheritance" do
    it "a subclass inherits the parent's declaration (registry scalar)" do
      parent = component_class { reactive_effects enter: :slide }
      child = Class.new(parent) { def self.name = "EffectsSpecChild" }
      expect(effect_data(child)[:reactive_effect_enter]).to eq("slide")
    end

    it "a subclass declaration overrides the parent's" do
      parent = component_class { reactive_effects enter: :slide }
      child = Class.new(parent) do
        def self.name = "EffectsSpecChild"
        reactive_effects enter: :scale
      end
      expect(effect_data(child)[:reactive_effect_enter]).to eq("scale")
    end
  end

  describe "memo correctness (the hot-path cache must never serve stale config)" do
    it "reflects a global config swap made AFTER the first render" do
      klass = component_class
      expect(effect_data(klass).keys.grep(/reactive_effect/)).to be_empty

      Phlex::Reactive.effects = { enter: :fade }
      expect(effect_data(klass)[:reactive_effect_enter]).to eq("fade")

      Phlex::Reactive.effects = nil
      expect(effect_data(klass).keys.grep(/reactive_effect/)).to be_empty
    end

    it "reflects a later class declaration (registry generation)" do
      klass = component_class
      expect(effect_data(klass).keys.grep(/reactive_effect/)).to be_empty

      klass.reactive_effects exit: :shake
      expect(effect_data(klass)[:reactive_effect_exit]).to eq("shake")
    end
  end
end
