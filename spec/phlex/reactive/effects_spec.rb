# frozen_string_literal: true

require "spec_helper"

# Issue #215: the effects vocabulary + the global opt-in. Effects animate
# enter/exit/update on stream renders; this file pins the CONFIG surface —
# Phlex::Reactive.effects (nil default = off), the built-in names, the
# named-legs custom form (issue #186 vocabulary), and the wire serialization
# the client interprets. The DSL/attr emission and per-call kwarg are pinned
# in effects_attrs_spec.rb / streamable + reply specs.
RSpec.describe Phlex::Reactive::Effects do
  after do
    Phlex::Reactive.effects = nil
  end

  describe "Phlex::Reactive.effects (global opt-in)" do
    it "defaults to nil — effects are OFF unless an app opts in" do
      expect(Phlex::Reactive.effects).to be_nil
    end

    it "accepts true as sugar for the default set (fade/fade/highlight)" do
      Phlex::Reactive.effects = true
      expect(Phlex::Reactive.effects).to eq(enter: "fade", exit: "fade", update: "highlight")
    end

    it "accepts a per-hook hash, normalized to wire strings" do
      Phlex::Reactive.effects = { enter: :slide, update: :highlight }
      expect(Phlex::Reactive.effects).to eq(enter: "slide", update: "highlight")
    end

    it "accepts nil and false to switch back off" do
      Phlex::Reactive.effects = true
      Phlex::Reactive.effects = nil
      expect(Phlex::Reactive.effects).to be_nil

      Phlex::Reactive.effects = true
      Phlex::Reactive.effects = false
      expect(Phlex::Reactive.effects).to be_nil
    end

    it "returns a frozen hash (the memoized resolution must not be corruptible)" do
      Phlex::Reactive.effects = true
      expect(Phlex::Reactive.effects).to be_frozen
    end

    it "rejects an unknown hook key, naming the valid ones" do
      expect { Phlex::Reactive.effects = { appear: :fade } }
        .to raise_error(ArgumentError, /appear.*enter.*exit.*update|enter.*exit.*update.*appear/m)
    end

    it "rejects an unknown effect name, listing the built-ins" do
      expect { Phlex::Reactive.effects = { enter: :sparkle } }
        .to raise_error(ArgumentError, /sparkle.*fade/m)
    end

    it "rejects a non-hash non-boolean value with a guided error" do
      expect { Phlex::Reactive.effects = :fade }
        .to raise_error(ArgumentError, /effects/)
    end

    it "bumps the effects generation on every write (cache key for per-class memos)" do
      expect { Phlex::Reactive.effects = true }
        .to change(Phlex::Reactive, :effects_generation).by(1)
      expect { Phlex::Reactive.effects = nil }
        .to change(Phlex::Reactive, :effects_generation).by(1)
    end
  end

  describe "hook values" do
    it "allows :random (the client picks a built-in per application)" do
      Phlex::Reactive.effects = { enter: :random }
      expect(Phlex::Reactive.effects).to eq(enter: "random")
    end

    it "allows false to disable one hook (kept, so a component false overrides a global effect)" do
      Phlex::Reactive.effects = { enter: :fade, update: false }
      expect(Phlex::Reactive.effects).to eq(enter: "fade", update: false)
    end

    it "compiles named legs { during:, from:, to: } to the [during, from, to] wire JSON" do
      Phlex::Reactive.effects = {
        enter: { during: %w[transition-all duration-300], from: "opacity-0", to: %w[opacity-100] }
      }
      expect(Phlex::Reactive.effects)
        .to eq(enter: %(["transition-all duration-300","opacity-0","opacity-100"]))
    end

    it "rejects legs missing a key, naming all three (the issue #186 vocabulary)" do
      expect { Phlex::Reactive.effects = { enter: { during: "x", from: "y" } } }
        .to raise_error(ArgumentError, /during.*from.*to/m)
    end

    it "rejects ALL-blank legs — a dead effect with no classes to animate" do
      expect { Phlex::Reactive.effects = { enter: { during: nil, from: "", to: [] } } }
        .to raise_error(ArgumentError, /blank.*dead|dead.*blank/m)
    end

    it "tolerates a single blank leg (element-owned transitions need no during: utilities — the #186 contract)" do
      Phlex::Reactive.effects = { enter: { during: nil, from: "opacity-0", to: "opacity-100" } }
      expect(Phlex::Reactive.effects).to eq(enter: %(["","opacity-0","opacity-100"]))
    end

    it "rejects the old positional-array legs form with the named-legs rewrite" do
      expect { Phlex::Reactive.effects = { enter: %w[during from to] } }
        .to raise_error(ArgumentError, /during:.*from:.*to:/m)
    end
  end

  describe "BUILT_INS" do
    it "ships the five named effects, frozen" do
      expect(described_class::BUILT_INS).to eq(%w[fade slide scale highlight shake])
      expect(described_class::BUILT_INS).to be_frozen
    end
  end

  describe ".wire_value (per-call effect: serialization)" do
    it "serializes a built-in symbol to its name" do
      expect(described_class.wire_value(:fade)).to eq("fade")
    end

    it "serializes :random" do
      expect(described_class.wire_value(:random)).to eq("random")
    end

    it "serializes false to \"off\" (per-call suppression)" do
      expect(described_class.wire_value(false)).to eq("off")
    end

    it "serializes named legs to the wire JSON array" do
      expect(described_class.wire_value({ during: "d", from: "f", to: "t" }))
        .to eq(%(["d","f","t"]))
    end

    it "rejects an unknown name" do
      expect { described_class.wire_value(:sparkle) }
        .to raise_error(ArgumentError, /sparkle/)
    end
  end
end
