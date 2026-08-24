# frozen_string_literal: true

require "rails_helper"

# Issue #186: ONE registry reader — the plural hash IS the fetch-one. The
# fetch-one getters (reactive_action, reactive_action?, reactive_collection_def,
# reactive_collection?, reactive_compute getter, reactive_compute_def,
# reactive_compute?) are removed → guided errors naming the hash form. The
# resolved registries come back FROZEN (they are the memoized dispatch table —
# mutation must FrozenError, never corrupt default-deny).
RSpec.describe "registry readers (issue #186)" do # rubocop:disable RSpec/DescribeClass
  let(:klass) do
    Class.new(Phlex::HTML) do
      include Phlex::Reactive::Streamable
      include Phlex::Reactive::Component

      def self.name = "RegistryReaderThing"

      reactive_state :count
      action :increment
      action :set, params: { count: :integer }
      reactive_compute :split, inputs: %i[a b], outputs: %i[a]
      reactive_collection :items, container: "items-list",
        item: Class.new(ApplicationComponent) { include Phlex::Reactive::Streamable }
      def initialize(count: 0) = @count = count
      def id = "reg"
    end
  end

  describe "the plural hash is the fetch-one" do
    it "reads one action from reactive_actions[:name]" do
      expect(klass.reactive_actions[:increment]).to be_a(Phlex::Reactive::Component::ActionDefinition)
      expect(klass.reactive_actions.key?(:set)).to be(true)
      expect(klass.reactive_actions.key?(:wat)).to be(false)
    end

    it "reads one compute from reactive_computes[:name]" do
      expect(klass.reactive_computes[:split].reducer).to eq("split")
      expect(klass.reactive_computes.key?(:split)).to be(true)
    end

    it "reads one collection from reactive_collections[:name]" do
      expect(klass.reactive_collections.key?(:items)).to be(true)
    end
  end

  describe "the resolved registries are FROZEN" do
    it "reactive_actions is frozen (mutating raises)" do
      expect(klass.reactive_actions).to be_frozen
      expect { klass.reactive_actions[:evil] = :x }.to raise_error(FrozenError)
    end

    it "reactive_computes is frozen" do
      expect(klass.reactive_computes).to be_frozen
    end

    it "reactive_collections is frozen" do
      expect(klass.reactive_collections).to be_frozen
    end
  end

  describe "removed getters raise guided errors" do
    it "reactive_action raises naming reactive_actions[:name]" do
      expect { klass.reactive_action(:increment) }
        .to raise_error(NoMethodError, /reactive_actions\[/)
    end

    it "reactive_action? raises naming reactive_actions.key?" do
      expect { klass.reactive_action?(:increment) }
        .to raise_error(NoMethodError, /reactive_actions\.key\?/)
    end

    it "reactive_compute_def raises naming reactive_computes[:name]" do
      expect { klass.reactive_compute_def(:split) }
        .to raise_error(NoMethodError, /reactive_computes\[/)
    end

    it "reactive_compute? raises naming reactive_computes.key?" do
      expect { klass.reactive_compute?(:split) }
        .to raise_error(NoMethodError, /reactive_computes\.key\?/)
    end

    it "reactive_collection_def raises naming reactive_collections[:name]" do
      expect { klass.reactive_collection_def(:items) }
        .to raise_error(NoMethodError, /reactive_collections\[/)
    end

    it "the bare reactive_compute(:name) GETTER form raises" do
      expect { klass.reactive_compute(:split) }
        .to raise_error(ArgumentError, /reactive_computes\[/)
    end
  end

  describe "the reactive_compute SETTER stays" do
    it "still declares a compute with inputs:/outputs:" do
      k = Class.new(Phlex::HTML) do
        include Phlex::Reactive::Component

        def self.name = "SetterStays"
        reactive_compute :totals, inputs: %i[a], outputs: %i[b]
      end
      expect(k.reactive_computes[:totals].reducer).to eq("totals")
    end
  end
end
