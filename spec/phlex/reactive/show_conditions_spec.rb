# frozen_string_literal: true

require "spec_helper"
require "phlex/reactive/show_conditions"

# Issue #180 Phase A: the ONE conditions language behind reactive_show /
# reactive_show_targets. `normalize(if:, if_any:, unless:)` compiles Ruby-native
# values (Hash = AND, Array = membership, Range = threshold; unless: = negation)
# into a DNF wire shape — an array of GROUPS, terms ANDed within a group, groups
# ORed. `match?(groups, values)` evaluates it in Ruby with semantics identical to
# the client (the shared fixture proves the parity). No expression surface: every
# term is a declared literal predicate, exactly the pre-#180 posture.
RSpec.describe Phlex::Reactive::ShowConditions do
  # Helpers under test are module functions.
  def normalize(**) = described_class.normalize(**)
  def match?(groups, values) = described_class.match?(groups, values)

  describe ".normalize — the value language" do
    it "compiles an if: Hash to ONE group of ANDed equals terms" do
      expect(normalize(if: { type: "individual" }))
        .to eq([[{ "field" => "type", "equals" => "individual" }]])
    end

    it "ANDs multiple keys within one if: group" do
      expect(normalize(if: { type: "individual", role: "director" }))
        .to eq([[
          { "field" => "type", "equals" => "individual" },
          { "field" => "role", "equals" => "director" }
        ]])
    end

    it "maps true/false to the checkbox checked-state string" do
      expect(normalize(if: { gift: true })).to eq([[{ "field" => "gift", "equals" => "true" }]])
      expect(normalize(if: { gift: false })).to eq([[{ "field" => "gift", "equals" => "false" }]])
    end

    it "maps nil to the empty string (visible while blank)" do
      expect(normalize(if: { note: nil })).to eq([[{ "field" => "note", "equals" => "" }]])
    end

    it "stringifies symbols and numbers in equals position" do
      expect(normalize(if: { kind: :premium })).to eq([[{ "field" => "kind", "equals" => "premium" }]])
      expect(normalize(if: { qty: 3 })).to eq([[{ "field" => "qty", "equals" => "3" }]])
    end

    it "maps an Array to a membership (in) term of stringified values" do
      expect(normalize(if: { size: [:l, "xl", 2] }))
        .to eq([[{ "field" => "size", "in" => %w[l xl 2] }]])
    end

    it "maps an endless Range to gte" do
      expect(normalize(if: { quantity: 10.. })).to eq([[{ "field" => "quantity", "gte" => 10 }]])
    end

    it "maps a beginless inclusive Range to lte" do
      expect(normalize(if: { amount: ..5000 })).to eq([[{ "field" => "amount", "lte" => 5000 }]])
    end

    it "maps a beginless exclusive Range to lt" do
      expect(normalize(if: { amount: ...5000 })).to eq([[{ "field" => "amount", "lt" => 5000 }]])
    end

    it "maps a bounded inclusive Range to TWO terms (gte + lte) in one group" do
      expect(normalize(if: { score: 10..20 }))
        .to eq([[
          { "field" => "score", "gte" => 10 },
          { "field" => "score", "lte" => 20 }
        ]])
    end

    it "maps a bounded exclusive-end Range to gte + lt" do
      expect(normalize(if: { score: 10...20 }))
        .to eq([[
          { "field" => "score", "gte" => 10 },
          { "field" => "score", "lt" => 20 }
        ]])
    end
  end

  describe ".normalize — if_any: (DNF)" do
    it "compiles an array of AND-hashes to one group each (OR of ANDs)" do
      expect(normalize(if_any: [{ director: true }, { shareholder: true, role: "individual" }]))
        .to eq([
          [{ "field" => "director", "equals" => "true" }],
          [{ "field" => "shareholder", "equals" => "true" }, { "field" => "role", "equals" => "individual" }]
        ])
    end
  end

  describe ".normalize — unless: (negation, composes with if:/if_any:)" do
    it "ANDs a negated scalar (not) into the single if: group" do
      expect(normalize(if: { shareholder: true }, unless: { director: true }))
        .to eq([[
          { "field" => "shareholder", "equals" => "true" },
          { "field" => "director", "not" => "true" }
        ]])
    end

    it "distributes unless: into EVERY if_any: group" do
      expect(normalize(if_any: [{ a: "1" }, { b: "2" }], unless: { c: "3" }))
        .to eq([
          [{ "field" => "a", "equals" => "1" }, { "field" => "c", "not" => "3" }],
          [{ "field" => "b", "equals" => "2" }, { "field" => "c", "not" => "3" }]
        ])
    end

    it "works standalone (unless: only, no if:) — negated terms over an implicit all-true group" do
      expect(normalize(unless: { mode: "off" }))
        .to eq([[{ "field" => "mode", "not" => "off" }]])
    end

    it "expands an unless: Array to N not-terms (∉ = AND of nots) in each group" do
      expect(normalize(unless: { role: %w[a b] }))
        .to eq([[{ "field" => "role", "not" => "a" }, { "field" => "role", "not" => "b" }]])
    end

    it "complements an unless: endless Range (¬gte → lt)" do
      expect(normalize(unless: { qty: 10.. })).to eq([[{ "field" => "qty", "lt" => 10 }]])
    end

    it "complements an unless: beginless inclusive Range (¬lte → gt)" do
      expect(normalize(unless: { qty: ..10 })).to eq([[{ "field" => "qty", "gt" => 10 }]])
    end

    it "complements an unless: beginless exclusive Range (¬lt → gte)" do
      expect(normalize(unless: { qty: ...10 })).to eq([[{ "field" => "qty", "gte" => 10 }]])
    end

    it "splits an unless: bounded Range into TWO groups (¬(a≤x≤b) = x<a ∨ x>b)" do
      # De Morgan across a single all-true base group → two groups.
      expect(normalize(unless: { score: 10..20 }))
        .to eq([
          [{ "field" => "score", "lt" => 10 }],
          [{ "field" => "score", "gt" => 20 }]
        ])
    end

    it "multiplies groups when a bounded-range unless: distributes over an if: group" do
      # (a) ∧ ¬(10≤x≤20) = (a ∧ x<10) ∨ (a ∧ x>20)
      expect(normalize(if: { a: "1" }, unless: { score: 10..20 }))
        .to eq([
          [{ "field" => "a", "equals" => "1" }, { "field" => "score", "lt" => 10 }],
          [{ "field" => "a", "equals" => "1" }, { "field" => "score", "gt" => 20 }]
        ])
    end

    it "obeys De Morgan for a MULTI-FIELD unless: — ¬(a ∧ b) = ¬a ∨ ¬b (two groups)" do
      # A multi-key unless: hash negates an AND, so it must expand to a
      # DISJUNCTION, not a conjunction of the two nots.
      expect(normalize(unless: { a: 1, b: 2 }))
        .to eq([
          [{ "field" => "a", "not" => "1" }],
          [{ "field" => "b", "not" => "2" }]
        ])
    end

    it "distributes a multi-field unless: over an if: group as (P ∧ ¬a) ∨ (P ∧ ¬b)" do
      expect(normalize(if: { p: "1" }, unless: { a: 2, b: 3 }))
        .to eq([
          [{ "field" => "p", "equals" => "1" }, { "field" => "a", "not" => "2" }],
          [{ "field" => "p", "equals" => "1" }, { "field" => "b", "not" => "3" }]
        ])
    end

    it "raises on an empty Array value under unless: (same rule as if:)" do
      expect { normalize(unless: { role: [] }) }
        .to raise_error(ArgumentError, /needs at least one value/)
    end
  end

  describe ".normalize — loud validation" do
    it "raises on an empty if: hash" do
      expect { normalize(if: {}) }.to raise_error(ArgumentError, /if: needs at least one field/)
    end

    it "raises on an empty if_any: array" do
      expect { normalize(if_any: []) }.to raise_error(ArgumentError, /if_any: needs at least one/)
    end

    it "raises on an empty group inside if_any:" do
      expect { normalize(if_any: [{ a: 1 }, {}]) }.to raise_error(ArgumentError, /each if_any: group needs/)
    end

    it "raises on an empty Array value (matches nothing)" do
      expect { normalize(if: { size: [] }) }.to raise_error(ArgumentError, /needs at least one value/)
    end

    it "raises on a non-Numeric Range endpoint" do
      expect { normalize(if: { d: "a".."z" }) }.to raise_error(ArgumentError, /Range endpoints must be numbers/)
    end

    it "raises when if: and if_any: are given together" do
      expect { normalize(if: { a: 1 }, if_any: [{ b: 2 }]) }
        .to raise_error(ArgumentError, %r{exactly one of if:/if_any:})
    end

    it "raises when no condition at all is given" do
      expect { normalize }.to raise_error(ArgumentError, /needs if:, if_any:, or unless:/)
    end
  end

  describe ".match? — Ruby evaluation mirrors the client" do
    let(:groups) do
      normalize(if_any: [{ director: true }, { shareholder: true, role: "individual" }])
    end

    it "is true when any group's every term matches" do
      expect(match?(groups, { "director" => "true" })).to be(true)
      expect(match?(groups, { "shareholder" => "true", "role" => "individual" })).to be(true)
    end

    it "is false when no group fully matches" do
      expect(match?(groups, { "director" => "false", "shareholder" => "true", "role" => "company" })).to be(false)
    end

    it "evaluates in: membership, numeric thresholds, and not" do
      g = normalize(if: { size: %w[l xl], quantity: 10.. }, unless: { mode: "off" })
      expect(match?(g, { "size" => "l", "quantity" => "12", "mode" => "on" })).to be(true)
      expect(match?(g, { "size" => "m", "quantity" => "12", "mode" => "on" })).to be(false)
      expect(match?(g, { "size" => "l", "quantity" => "3",  "mode" => "on" })).to be(false)
      expect(match?(g, { "size" => "l", "quantity" => "12", "mode" => "off" })).to be(false)
    end

    it "treats a blank/non-numeric value as NOT matching a numeric term (fail-closed)" do
      g = normalize(if: { quantity: 10.. })
      expect(match?(g, { "quantity" => "" })).to be(false)
      expect(match?(g, { "quantity" => "abc" })).to be(false)
    end

    it "fail-closes an unless: numeric complement on a blank value (stays hidden)" do
      # unless: { qty: 10.. } → lt: 10. A blank qty is NaN → the lt term is
      # false → group false → hidden. The complement must NOT flip a blank to
      # visible.
      g = normalize(unless: { qty: 10.. })
      expect(match?(g, { "qty" => "" })).to be(false)
    end

    it "returns false when a referenced field is absent from values" do
      g = normalize(if: { director: true })
      expect(match?(g, {})).to be(false)
    end

    it "evaluates a multi-field unless: as the negation of an AND (De Morgan)" do
      # unless: { a: 1, b: 2 } — hide ONLY when a==1 AND b==2; show otherwise.
      g = normalize(unless: { a: 1, b: 2 })
      expect(match?(g, { "a" => "1", "b" => "2" })).to be(false) # both match → hidden
      expect(match?(g, { "a" => "1", "b" => "9" })).to be(true)  # only a → shown
      expect(match?(g, { "a" => "9", "b" => "2" })).to be(true)  # only b → shown
      expect(match?(g, { "a" => "9", "b" => "9" })).to be(true)  # neither → shown
    end
  end

  describe ".fields — the referenced field set (drives reactive_values coverage)" do
    it "collects every field named across all groups and terms" do
      g = normalize(if_any: [{ director: true }, { shareholder: true, role: "individual" }], unless: { blocked: true })
      expect(described_class.fields(g)).to contain_exactly("director", "shareholder", "role", "blocked")
    end
  end
end
