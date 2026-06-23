# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/phlex/reactive/component/component_generator"

RSpec.describe Phlex::Reactive::Generators::ComponentGenerator do
  let(:tmp) { Rails.root.join("tmp/generator-spec") }

  before { FileUtils.rm_rf(tmp) }
  after { FileUtils.rm_rf(tmp) }

  def generate(args)
    described_class.start(args, destination_root: tmp)
  end

  def component(path)
    File.read(tmp.join("app/components", path))
  end

  describe "state-backed (default)" do
    it "generates a component signing :value with the given actions" do
      generate(["Counter", "increment", "decrement"])

      src = component("counter.rb")
      expect(src).to include("class Counter < ApplicationComponent")
      expect(src).to include("include Phlex::Reactive::Streamable")
      expect(src).to include("include Phlex::Reactive::Component")
      expect(src).to include("reactive_state :value")
      expect(src).to include("action :increment")
      expect(src).to include("action :decrement")
      expect(src).to include('def id = "counter"')
      expect(src).to include("button(**on(:increment))")
    end

    it "honors --state for custom signed vars" do
      generate(["Wizard", "next_step", "--state", "step", "open"])
      src = component("wizard.rb")
      expect(src).to include("reactive_state :step, :open")
    end
  end

  describe "record-backed (--record)" do
    it "generates a component with GlobalID identity and dom_id" do
      generate(["Todos::Item", "toggle", "rename", "--record", "todo"])

      src = component("todos/item.rb")
      expect(src).to include("class Todos::Item < ApplicationComponent")
      expect(src).to include("reactive_record :todo")
      expect(src).to include("def initialize(todo:)")
      expect(src).to include("def id = dom_id(@todo)")
      expect(src).to include("action :toggle")
      expect(src).to include("# authorize! @todo, :update?")
    end
  end

  it "generates a matching spec when the app uses RSpec" do
    FileUtils.mkdir_p(tmp.join("spec")) # signal an RSpec app
    generate(["Counter", "increment"])

    spec = File.read(tmp.join("spec/components/counter_spec.rb"))
    expect(spec).to include("RSpec.describe Counter")
    expect(spec).to include("reactive_action?(:increment)")
  end

  it "skips the spec when the app has no spec/ directory" do
    generate(["Counter", "increment"])
    expect(File).not_to exist(tmp.join("spec/components/counter_spec.rb"))
  end
end
