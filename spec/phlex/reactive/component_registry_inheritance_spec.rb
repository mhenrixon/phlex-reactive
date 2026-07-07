# frozen_string_literal: true

require "spec_helper"

# The five class-level registries behind the Component DSL — reactive_actions,
# reactive_state_keys, reactive_collections, reactive_computes, and
# reactive_record_key — are the source of truth for default-deny dispatch,
# identity signing, and the collection/compute wiring. This suite locks their
# INHERITANCE contract (issue #115): parent-declared-before-child-read,
# subclass override, no upward leak, three-level chains, write-through on self,
# and class redefinition (the dev-reload shape).
#
# All five resolve through Component::Registry with ONE semantic: resolve
# through the superclass at read time, memoized per class against a
# process-wide generation counter bumped on any registry write. Pre-#115 the
# implementations DIVERGED (the four collection registries snapshot-dup'd the
# parent on first access, so a late parent declaration was silently invisible;
# reactive_record_key walked live; the hot-path memos went stale split-brain).
# The examples marked `UNIFIED (#115)` are the ones that flipped in the
# unification — the one deliberate behavior change of the refactor. Every
# unmarked example is green byte-for-byte on both sides of the swap.
RSpec.describe Phlex::Reactive::Component, "registry inheritance" do
  # A fresh component class (optionally subclassing `parent`), with the DSL
  # declarations given in the block. Anonymous on purpose: registries must
  # live on the class object itself, never on a name or a global.
  def reactive_class(parent = nil, &body)
    klass = parent ? Class.new(parent) : Class.new { include Phlex::Reactive::Component }
    klass.class_eval(&body) if body
    klass
  end

  describe "reactive_actions (the default-deny source of truth)" do
    it "inherits a parent action declared before the child is read" do
      parent = reactive_class { action :ping }
      child = reactive_class(parent)

      expect(child.reactive_actions.key?(:ping)).to be(true)
      expect(child.reactive_actions[:ping].params).to eq({})
    end

    it "keeps a child's own action out of the parent (no upward leak)" do
      parent = reactive_class { action :ping }
      child = reactive_class(parent) { action :pong }

      expect(child.reactive_actions.key?(:pong)).to be(true)
      expect(parent.reactive_actions.key?(:pong)).to be(false)
    end

    it "lets a child override a parent action's schema; the parent keeps its own" do
      parent = reactive_class { action :save, params: { title: :string } }
      child = reactive_class(parent) { action :save, params: { title: :string, count: :integer } }

      expect(child.reactive_actions[:save].params).to eq(title: :string, count: :integer)
      expect(parent.reactive_actions[:save].params).to eq(title: :string)
    end

    it "merges a three-level chain, nearest declaration winning" do
      grandparent = reactive_class { action(:a) && action(:shared, params: { from: :string }) }
      parent = reactive_class(grandparent) { action :b }
      child = reactive_class(parent) { action(:c) && action(:shared, params: { from: :integer }) }

      expect(child.reactive_actions.keys).to contain_exactly(:a, :shared, :b, :c)
      expect(child.reactive_actions[:shared].params).to eq(from: :integer)
      expect(parent.reactive_actions[:shared].params).to eq(from: :string)
      expect(parent.reactive_actions.key?(:c)).to be(false)
    end

    it "sees its OWN declaration made after its registry was read (write-through on self)" do
      klass = reactive_class
      klass.reactive_actions # materialize the memo
      klass.class_eval { action :late }

      expect(klass.reactive_actions.key?(:late)).to be(true)
    end

    # UNIFIED (#115): pre-#115 this was the snapshot-dup divergence — the
    # child's first read froze the parent's registry, so a late parent action
    # was silently invisible to the child (while visible on the parent). The
    # Registry resolves at read time, so the declaration is visible everywhere.
    it "sees a parent action declared after the child registry was read (resolve-at-read)" do
      parent = reactive_class
      child = reactive_class(parent)
      child.reactive_actions # a prior read no longer freezes the parent's registry
      parent.class_eval { action :late }

      expect(parent.reactive_actions.key?(:late)).to be(true)
      expect(child.reactive_actions.key?(:late)).to be(true)
    end
  end

  describe "reactive_state_keys (the signed-state key list)" do
    it "inherits parent keys ahead of the child's own (parent-first order)" do
      parent = reactive_class { reactive_state :a }
      child = reactive_class(parent) { reactive_state :b }

      expect(child.reactive_state_keys).to eq(%i[a b])
      expect(parent.reactive_state_keys).to eq(%i[a])
    end

    it "preserves declaration order across a three-level chain" do
      grandparent = reactive_class { reactive_state :a }
      parent = reactive_class(grandparent) { reactive_state :b }
      child = reactive_class(parent) { reactive_state :c }

      expect(child.reactive_state_keys).to eq(%i[a b c])
    end

    it "sees its OWN keys added after its registry was read (write-through on self)" do
      klass = reactive_class { reactive_state :a }
      expect(klass.reactive_state_keys).to eq(%i[a])
      klass.class_eval { reactive_state :late }

      expect(klass.reactive_state_keys).to eq(%i[a late])
    end

    # UNIFIED (#115): pre-#115 the child's first read snapshot the parent's
    # key list, so a late parent key never reached the child.
    it "sees a parent key added after the child registry was read (resolve-at-read)" do
      parent = reactive_class { reactive_state :a }
      child = reactive_class(parent)
      expect(child.reactive_state_keys).to eq(%i[a]) # a prior read doesn't freeze anything
      parent.class_eval { reactive_state :late }

      expect(parent.reactive_state_keys).to eq(%i[a late])
      expect(child.reactive_state_keys).to eq(%i[a late])
    end
  end

  describe "reactive_collections (the list contract registry)" do
    let(:row_component) { Class.new }

    it "inherits a parent collection and lets the child add its own without upward leak" do
      row = row_component
      parent = reactive_class { reactive_collection :items, item: row, container: "items" }
      child = reactive_class(parent) { reactive_collection :extras, item: row, container: "extras" }

      expect(child.reactive_collections.key?(:items)).to be(true)
      expect(child.reactive_collections[:items].container).to eq("items")
      expect(child.reactive_collections.key?(:extras)).to be(true)
      expect(parent.reactive_collections.key?(:extras)).to be(false)
    end

    it "lets a child override a parent collection by name; the parent keeps its own" do
      row = row_component
      parent = reactive_class { reactive_collection :items, item: row, container: "items" }
      child = reactive_class(parent) { reactive_collection :items, item: row, container: "narrow-items" }

      expect(child.reactive_collections[:items].container).to eq("narrow-items")
      expect(parent.reactive_collections[:items].container).to eq("items")
    end

    # UNIFIED (#115): pre-#115 this was the same snapshot-dup divergence as
    # reactive_actions.
    it "sees a parent collection declared after the child registry was read (resolve-at-read)" do
      row = row_component
      parent = reactive_class
      child = reactive_class(parent)
      child.reactive_collections # a prior read no longer freezes the parent's registry
      parent.class_eval { reactive_collection :late, item: row, container: "late" }

      expect(parent.reactive_collections.key?(:late)).to be(true)
      expect(child.reactive_collections.key?(:late)).to be(true)
    end
  end

  describe "reactive_computes (the client-side data-binding registry)" do
    it "inherits a parent compute and lets the child add its own without upward leak" do
      parent = reactive_class { reactive_compute :split, inputs: %i[a], outputs: %i[b] }
      child = reactive_class(parent) { reactive_compute :totals, inputs: %i[p q], outputs: %i[t] }

      expect(child.reactive_computes.key?(:split)).to be(true)
      expect(child.reactive_computes[:split].reducer).to eq("split")
      expect(child.reactive_computes.key?(:totals)).to be(true)
      expect(parent.reactive_computes.key?(:totals)).to be(false)
    end

    it "lets a child override a parent compute by name; the parent keeps its own" do
      parent = reactive_class { reactive_compute :split, inputs: %i[a], outputs: %i[b] }
      child = reactive_class(parent) { reactive_compute :split, inputs: %i[a2], outputs: %i[b2] }

      expect(child.reactive_computes[:split].inputs).to eq(%i[a2])
      expect(parent.reactive_computes[:split].inputs).to eq(%i[a])
    end

    it "exposes the definition via reactive_computes[:name] (issue #115 registry, issue #186 hash access)" do
      parent = reactive_class { reactive_compute :split, inputs: %i[a], outputs: %i[b] }
      child = reactive_class(parent)

      expect(child.reactive_computes[:split].outputs).to eq(%i[b])
      expect(child.reactive_computes[:nope]).to be_nil
    end

    # UNIFIED (#115): pre-#115 this was the same snapshot-dup divergence as
    # reactive_actions.
    it "sees a parent compute declared after the child registry was read (resolve-at-read)" do
      parent = reactive_class
      child = reactive_class(parent)
      child.reactive_computes # a prior read no longer freezes the parent's registry
      parent.class_eval { reactive_compute :late, inputs: %i[a], outputs: %i[b] }

      expect(parent.reactive_computes.key?(:late)).to be(true)
      expect(child.reactive_computes.key?(:late)).to be(true)
    end
  end

  describe "reactive_record_key (the signed-identity record key)" do
    it "inherits the parent's record key" do
      parent = reactive_class { reactive_record :todo }
      child = reactive_class(parent)

      expect(child.reactive_record_key).to eq(:todo)
    end

    it "lets a child override; the parent keeps its own" do
      parent = reactive_class { reactive_record :todo }
      child = reactive_class(parent) { reactive_record :rich_todo }

      expect(child.reactive_record_key).to eq(:rich_todo)
      expect(parent.reactive_record_key).to eq(:todo)
    end

    it "walks a three-level chain to the nearest declaration" do
      grandparent = reactive_class { reactive_record :base }
      parent = reactive_class(grandparent) { reactive_record :middle }
      child = reactive_class(parent)

      expect(child.reactive_record_key).to eq(:middle)
    end

    # This live-walk behavior is the semantic the #115 Registry unification
    # adopted for all five registries — reactive_record_key behaved this way
    # BEFORE the swap too (the reference semantics; green on both sides).
    it "DOES see a parent reactive_record declared after the child was read (resolve-at-read)" do
      parent = reactive_class
      child = reactive_class(parent)
      expect(child.reactive_record_key).to be_nil
      parent.class_eval { reactive_record :thing }

      expect(child.reactive_record_key).to eq(:thing)
    end
  end

  describe "hot-path ivar memos (reactive_record_ivar / reactive_state_ivars)" do
    it "precomputes the record ivar from the resolved key (inherited included)" do
      parent = reactive_class { reactive_record :todo }
      child = reactive_class(parent)

      expect(child.reactive_record_ivar).to eq(:@todo)
    end

    it "is nil for a record-less component" do
      expect(reactive_class.reactive_record_ivar).to be_nil
    end

    it "refreshes when the class itself re-declares reactive_record" do
      klass = reactive_class { reactive_record :a }
      expect(klass.reactive_record_ivar).to eq(:@a)
      klass.class_eval { reactive_record :b }

      expect(klass.reactive_record_ivar).to eq(:@b)
    end

    it "precomputes [string_key, ivar] pairs over the resolved state keys" do
      parent = reactive_class { reactive_state :a }
      child = reactive_class(parent) { reactive_state :b }

      expect(child.reactive_state_ivars).to eq([["a", :@a], ["b", :@b]])
    end

    it "refreshes when the class itself adds a state key" do
      klass = reactive_class { reactive_state :a }
      expect(klass.reactive_state_ivars).to eq([["a", :@a]])
      klass.class_eval { reactive_state :b }

      expect(klass.reactive_state_ivars).to eq([["a", :@a], ["b", :@b]])
    end

    # UNIFIED (#115): pre-#115 the child memoized nil and nothing cleared a
    # SUBCLASS's memo, so the live reactive_record_key and the memoized
    # reactive_record_ivar disagreed (split-brain) — a reactive_token render
    # on the child signed NO gid despite reactive_record_key naming one. The
    # write-time family sweep (Registry.bump!) keeps them coherent while the
    # read stays a bare defined? fast path.
    it "keeps the record ivar coherent with the live key after a late parent reactive_record" do
      parent = reactive_class
      child = reactive_class(parent)
      expect(child.reactive_record_ivar).to be_nil # memoize nil now
      parent.class_eval { reactive_record :thing }

      expect(child.reactive_record_key).to eq(:thing)
      expect(child.reactive_record_ivar).to eq(:@thing) # swept + recomputed, no split-brain
    end

    # UNIFIED (#115): pre-#115 reactive_state on the parent reset only the
    # PARENT's ivar memo; the child's snapshot (keys and pairs) stayed stale.
    it "refreshes state ivars after a late parent reactive_state (family-wide sweep)" do
      parent = reactive_class { reactive_state :a }
      child = reactive_class(parent)
      expect(child.reactive_state_ivars).to eq([["a", :@a]]) # memoize now
      parent.class_eval { reactive_state :late }

      expect(parent.reactive_state_ivars).to eq([["a", :@a], ["late", :@late]])
      expect(child.reactive_state_keys).to eq(%i[a late])
      expect(child.reactive_state_ivars).to eq([["a", :@a], ["late", :@late]])
    end
  end

  describe "class redefinition (the dev-reload shape)" do
    it "a redefined class rebuilds its registries from scratch — no residue keyed by name or a global" do
      first = reactive_class { action :a }
      second = reactive_class { action :b } # what a Zeitwerk reload produces: a NEW class object

      expect(first.reactive_actions.key?(:a)).to be(true)
      expect(second.reactive_actions.key?(:a)).to be(false)
      expect(second.reactive_actions.key?(:b)).to be(true)
    end
  end
end
