# frozen_string_literal: true

require "spec_helper"

# The five class-level registries behind the Component DSL — reactive_actions,
# reactive_state_keys, reactive_collections, reactive_computes, and
# reactive_record_key — are the source of truth for default-deny dispatch,
# identity signing, and the collection/compute wiring. This suite locks their
# INHERITANCE contract (issue #115, step 1): parent-declared-before-child-read,
# subclass override, no upward leak, three-level chains, write-through on self,
# and class redefinition (the dev-reload shape).
#
# Where the five hand-rolled implementations DIVERGE today, the example is
# marked `DIVERGENCE (pre-#115)` and asserts the SHIPPED behavior:
#
#   * the four collection registries snapshot-`dup` the parent on FIRST access,
#     so a parent declaration made after a child read is silently invisible;
#   * reactive_record_key walks the superclass LIVE on every read, so the same
#     late declaration IS visible;
#   * the hot-path memos (reactive_record_ivar / reactive_state_ivars) go
#     STALE on a late parent declaration — split-brain against the live key.
#
# The #115 Registry unification flips exactly the marked examples (late parent
# declarations become visible everywhere, the memos stay coherent) and nothing
# else. Every unmarked example must stay green byte-for-byte across the swap.
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

      expect(child.reactive_action?(:ping)).to be(true)
      expect(child.reactive_action(:ping).params).to eq({})
    end

    it "keeps a child's own action out of the parent (no upward leak)" do
      parent = reactive_class { action :ping }
      child = reactive_class(parent) { action :pong }

      expect(child.reactive_action?(:pong)).to be(true)
      expect(parent.reactive_action?(:pong)).to be(false)
    end

    it "lets a child override a parent action's schema; the parent keeps its own" do
      parent = reactive_class { action :save, params: { title: :string } }
      child = reactive_class(parent) { action :save, params: { title: :string, count: :integer } }

      expect(child.reactive_action(:save).params).to eq(title: :string, count: :integer)
      expect(parent.reactive_action(:save).params).to eq(title: :string)
    end

    it "merges a three-level chain, nearest declaration winning" do
      grandparent = reactive_class { action(:a) && action(:shared, params: { from: :string }) }
      parent = reactive_class(grandparent) { action :b }
      child = reactive_class(parent) { action(:c) && action(:shared, params: { from: :integer }) }

      expect(child.reactive_actions.keys).to contain_exactly(:a, :shared, :b, :c)
      expect(child.reactive_action(:shared).params).to eq(from: :integer)
      expect(parent.reactive_action(:shared).params).to eq(from: :string)
      expect(parent.reactive_action?(:c)).to be(false)
    end

    it "sees its OWN declaration made after its registry was read (write-through on self)" do
      klass = reactive_class
      klass.reactive_actions # materialize the memo
      klass.class_eval { action :late }

      expect(klass.reactive_action?(:late)).to be(true)
    end

    # DIVERGENCE (pre-#115): reactive_actions snapshot-`dup`s the parent on the
    # child's FIRST read, so a parent action declared after that read is
    # silently invisible to the child — while remaining visible on the parent.
    it "does NOT see a parent action declared after the child registry was read (snapshot-dup)" do
      parent = reactive_class
      child = reactive_class(parent)
      child.reactive_actions # snapshot the parent's (empty) registry now
      parent.class_eval { action :late }

      expect(parent.reactive_action?(:late)).to be(true)
      expect(child.reactive_action?(:late)).to be(false)
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

    # DIVERGENCE (pre-#115): same snapshot-dup as reactive_actions.
    it "does NOT see a parent key added after the child registry was read (snapshot-dup)" do
      parent = reactive_class { reactive_state :a }
      child = reactive_class(parent)
      expect(child.reactive_state_keys).to eq(%i[a]) # snapshot now
      parent.class_eval { reactive_state :late }

      expect(parent.reactive_state_keys).to eq(%i[a late])
      expect(child.reactive_state_keys).to eq(%i[a])
    end
  end

  describe "reactive_collections (the list contract registry)" do
    let(:row_component) { Class.new }

    it "inherits a parent collection and lets the child add its own without upward leak" do
      row = row_component
      parent = reactive_class { reactive_collection :items, item: row, container: "items" }
      child = reactive_class(parent) { reactive_collection :extras, item: row, container: "extras" }

      expect(child.reactive_collection?(:items)).to be(true)
      expect(child.reactive_collection_def(:items).container).to eq("items")
      expect(child.reactive_collection?(:extras)).to be(true)
      expect(parent.reactive_collection?(:extras)).to be(false)
    end

    it "lets a child override a parent collection by name; the parent keeps its own" do
      row = row_component
      parent = reactive_class { reactive_collection :items, item: row, container: "items" }
      child = reactive_class(parent) { reactive_collection :items, item: row, container: "narrow-items" }

      expect(child.reactive_collection_def(:items).container).to eq("narrow-items")
      expect(parent.reactive_collection_def(:items).container).to eq("items")
    end

    # DIVERGENCE (pre-#115): same snapshot-dup as reactive_actions.
    it "does NOT see a parent collection declared after the child registry was read (snapshot-dup)" do
      row = row_component
      parent = reactive_class
      child = reactive_class(parent)
      child.reactive_collections # snapshot now
      parent.class_eval { reactive_collection :late, item: row, container: "late" }

      expect(parent.reactive_collection?(:late)).to be(true)
      expect(child.reactive_collection?(:late)).to be(false)
    end
  end

  describe "reactive_computes (the client-side data-binding registry)" do
    it "inherits a parent compute and lets the child add its own without upward leak" do
      parent = reactive_class { reactive_compute :split, inputs: %i[a], outputs: %i[b] }
      child = reactive_class(parent) { reactive_compute :totals, inputs: %i[p q], outputs: %i[t] }

      expect(child.reactive_compute?(:split)).to be(true)
      expect(child.reactive_compute(:split).reducer).to eq("split")
      expect(child.reactive_compute?(:totals)).to be(true)
      expect(parent.reactive_compute?(:totals)).to be(false)
    end

    it "lets a child override a parent compute by name; the parent keeps its own" do
      parent = reactive_class { reactive_compute :split, inputs: %i[a], outputs: %i[b] }
      child = reactive_class(parent) { reactive_compute :split, inputs: %i[a2], outputs: %i[b2] }

      expect(child.reactive_compute(:split).inputs).to eq(%i[a2])
      expect(parent.reactive_compute(:split).inputs).to eq(%i[a])
    end

    # DIVERGENCE (pre-#115): same snapshot-dup as reactive_actions.
    it "does NOT see a parent compute declared after the child registry was read (snapshot-dup)" do
      parent = reactive_class
      child = reactive_class(parent)
      child.reactive_computes # snapshot now
      parent.class_eval { reactive_compute :late, inputs: %i[a], outputs: %i[b] }

      expect(parent.reactive_compute?(:late)).to be(true)
      expect(child.reactive_compute?(:late)).to be(false)
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

    # CONTRAST (pre-#115): unlike the four snapshot registries above,
    # reactive_record_key walks the superclass LIVE on every read — the SAME
    # late-parent-declaration scenario that is invisible via action semantics
    # is visible via record-key semantics. This is the semantic the #115
    # Registry unification adopts for all five.
    it "DOES see a parent reactive_record declared after the child was read (live walk)" do
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

    # DIVERGENCE (pre-#115): the child memoized nil before the parent declared,
    # and nothing clears a SUBCLASS's memo — so the live reactive_record_key
    # and the memoized reactive_record_ivar disagree (split-brain). A
    # reactive_token render on the child would sign NO gid despite
    # reactive_record_key naming one.
    it "serves a STALE record ivar after a late parent reactive_record (split-brain with the live key)" do
      parent = reactive_class
      child = reactive_class(parent)
      expect(child.reactive_record_ivar).to be_nil # memoize nil now
      parent.class_eval { reactive_record :thing }

      expect(child.reactive_record_key).to eq(:thing) # the live walk sees it
      expect(child.reactive_record_ivar).to be_nil    # the defined? memo does not
    end

    # DIVERGENCE (pre-#115): reactive_state on the parent resets only the
    # PARENT's ivar memo; the child's snapshot (keys and pairs) stays stale.
    it "serves STALE state ivars after a late parent reactive_state" do
      parent = reactive_class { reactive_state :a }
      child = reactive_class(parent)
      expect(child.reactive_state_ivars).to eq([["a", :@a]]) # memoize now
      parent.class_eval { reactive_state :late }

      expect(parent.reactive_state_ivars).to eq([["a", :@a], ["late", :@late]])
      expect(child.reactive_state_keys).to eq(%i[a])
      expect(child.reactive_state_ivars).to eq([["a", :@a]])
    end
  end

  describe "class redefinition (the dev-reload shape)" do
    it "a redefined class rebuilds its registries from scratch — no residue keyed by name or a global" do
      first = reactive_class { action :a }
      second = reactive_class { action :b } # what a Zeitwerk reload produces: a NEW class object

      expect(first.reactive_action?(:a)).to be(true)
      expect(second.reactive_action?(:a)).to be(false)
      expect(second.reactive_action?(:b)).to be(true)
    end
  end
end
