# frozen_string_literal: true

require "rails_helper"

# Issue #184: named param schemas — Phlex::Reactive.param_schema registers a
# reusable schema (boot-time, frozen after init like the param_type registry) so
# sibling components stop duplicating verbatim constants that drift. `action
# params: :name` resolves it; it composes with plain Ruby.
RSpec.describe "Phlex::Reactive.param_schema (issue #184)" do # rubocop:disable RSpec/DescribeClass
  around do
    Phlex::Reactive.reset_param_schemas! if Phlex::Reactive.respond_to?(:reset_param_schemas!)
    it.run
  ensure
    Phlex::Reactive.reset_param_schemas! if Phlex::Reactive.respond_to?(:reset_param_schemas!)
  end

  it "registers a schema and reads it back as a Hash" do
    Phlex::Reactive.param_schema(:todo, title: :string, done: :boolean)
    expect(Phlex::Reactive.param_schema(:todo)).to eq(title: :string, done: :boolean)
  end

  it "deep-freezes a nested schema so the shared entry can't be mutated" do
    Phlex::Reactive.param_schema(:order, total: :integer, address: { street: :string })
    stored = Phlex::Reactive.param_schema(:order)
    expect(stored).to be_frozen
    expect(stored[:address]).to be_frozen
    expect { stored[:address][:evil] = :boom }.to raise_error(FrozenError)
  end

  it "resolves `action params: :symbol` to the registered schema" do
    Phlex::Reactive.param_schema(:todo, title: :string, done: :boolean)
    klass = Class.new do
      include Phlex::Reactive::Component

      def self.name = "SchemaByName"
      action :save, params: :todo
    end
    coerced = klass.reactive_actions[:save].schema.coerce({ "title" => "hi", "done" => "true", "x" => "1" }, nil)
    expect(coerced).to eq(title: "hi", done: true) # x dropped by the schema
  end

  it "composes with plain Ruby via ** spread" do
    Phlex::Reactive.param_schema(:todo, title: :string)
    klass = Class.new do
      include Phlex::Reactive::Component

      def self.name = "SchemaComposed"
      action :bulk, params: { **Phlex::Reactive.param_schema(:todo), note: :string }
    end
    coerced = klass.reactive_actions[:bulk].schema.coerce({ "title" => "t", "note" => "n" }, nil)
    expect(coerced).to eq(title: "t", note: "n")
  end

  it "raises for an unknown schema name, listing the registered ones" do
    Phlex::Reactive.param_schema(:todo, title: :string)
    expect { Phlex::Reactive.param_schema(:nope) }
      .to raise_error(ArgumentError, /nope.*todo|todo/m)
  end

  it "raises when action params: names an unknown schema" do
    expect do
      Class.new do
        include Phlex::Reactive::Component

        def self.name = "SchemaBadName"
        action :save, params: :ghost
      end
    end.to raise_error(ArgumentError, /ghost|schema/)
  end

  it "keeps params: taking a plain Hash (additive)" do
    klass = Class.new do
      include Phlex::Reactive::Component

      def self.name = "SchemaHashStillWorks"
      action :save, params: { title: :string }
    end
    expect(klass.reactive_actions[:save].schema.coerce({ "title" => "x" }, nil)).to eq(title: "x")
  end

  describe "registry frozen after boot" do
    around do
      was_frozen = Phlex::Reactive.param_schemas_frozen?
      Phlex::Reactive.reset_param_schemas!
      it.run
    ensure
      Phlex::Reactive.reset_param_schemas!
      Phlex::Reactive.freeze_param_schemas! if was_frozen
    end

    it "rejects registration after freeze_param_schemas!" do
      Phlex::Reactive.freeze_param_schemas!
      expect { Phlex::Reactive.param_schema(:late, x: :string) }
        .to raise_error(Phlex::Reactive::Error, /frozen|boot|initializer/i)
    end
  end
end
