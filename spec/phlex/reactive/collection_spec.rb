# frozen_string_literal: true

require "spec_helper"

# The reactive_collection DSL (issue #35) declares the list contract once on the
# container component: the per-row item component, the container DOM id, an
# optional count companion id, an optional empty-state component, and a size
# resolver. These specs cover ONLY the declaration/storage; the stream building
# lives in collection_streams_spec.rb (Response/Reply) and the dummy request spec.
RSpec.describe Phlex::Reactive::Component, "reactive_collection" do
  let(:row_klass) do
    Class.new do
      def self.name = "ItemRow"
    end
  end

  let(:empty_klass) do
    Class.new do
      def self.name = "ItemsEmpty"
    end
  end

  let(:container_klass) do
    row = row_klass
    empty = empty_klass
    Class.new do
      include Phlex::Reactive::Component

      def self.name = "ItemsList"

      reactive_collection :items,
        item: row,
        container: "items-list",
        count: "items-count",
        empty: empty,
        size: -> { 3 }
    end
  end

  describe "declaration storage" do
    it "registers the collection under its name" do
      expect(container_klass.reactive_collections.key?(:items)).to be(true)
      expect(container_klass.reactive_collections.key?(:nope)).to be(false)
    end

    it "captures the item component, container id, count id and empty component" do
      collection = container_klass.reactive_collections[:items]
      expect(collection.item).to eq(row_klass)
      expect(collection.container).to eq("items-list")
      expect(collection.count).to eq("items-count")
      expect(collection.empty).to eq(empty_klass)
    end

    it "evaluates the size resolver against a component instance" do
      collection = container_klass.reactive_collections[:items]
      expect(collection.size_for(container_klass.allocate)).to eq(3)
    end
  end

  describe "optional fields" do
    let(:minimal_klass) do
      row = row_klass
      Class.new do
        include Phlex::Reactive::Component

        def self.name = "MinimalList"
        reactive_collection :rows, item: row, container: "rows"
      end
    end

    it "allows omitting count, empty and size" do
      collection = minimal_klass.reactive_collections[:rows]
      expect(collection.count).to be_nil
      expect(collection.empty).to be_nil
    end

    it "size defaults to nil when no resolver is declared" do
      collection = minimal_klass.reactive_collections[:rows]
      expect(collection.size_for(minimal_klass.allocate)).to be_nil
    end
  end

  describe "inheritance" do
    it "a subclass inherits declared collections and can add its own" do
      parent = container_klass
      child = Class.new(parent) do
        def self.name = "ChildList"
        reactive_collection :extras, item: parent.reactive_collections[:items].item, container: "extras"
      end

      expect(child.reactive_collections.key?(:items)).to be(true)
      expect(child.reactive_collections.key?(:extras)).to be(true)
      # parent is not polluted by the child's addition
      expect(parent.reactive_collections.key?(:extras)).to be(false)
    end
  end
end
