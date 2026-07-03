# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/phlex/reactive/install/install_generator"

RSpec.describe Phlex::Reactive::Generators::InstallGenerator do
  let(:tmp) { Rails.root.join("tmp/install-generator-spec") }

  before { FileUtils.rm_rf(tmp) }
  after { FileUtils.rm_rf(tmp) }

  def run!
    described_class.start([], destination_root: tmp)
  end

  it "writes the config initializer" do
    run!
    initializer = File.read(tmp.join("config/initializers/phlex_reactive.rb"))
    expect(initializer).to include("Phlex::Reactive.base_controller_name")
    expect(initializer).to include("Phlex::Reactive.action_path")
  end

  context "with a Stimulus controllers index" do
    before do
      FileUtils.mkdir_p(tmp.join("app/javascript/controllers"))
      File.write(tmp.join("app/javascript/controllers/index.js"), <<~JS)
        import { application } from "controllers/application"
        // existing registrations
      JS
    end

    it "registers the reactive controller eagerly" do
      run!
      index = File.read(tmp.join("app/javascript/controllers/index.js"))
      expect(index).to include('import ReactiveController from "phlex/reactive/reactive_controller"')
      expect(index).to include('application.register("reactive", ReactiveController)')
    end

    it "is idempotent (does not duplicate the registration)" do
      run!
      run!
      index = File.read(tmp.join("app/javascript/controllers/index.js"))
      expect(index.scan('application.register("reactive", ReactiveController)').size).to eq(1)
    end
  end

  context "with an esbuild/bun entrypoint (app/javascript/application.js)" do
    before do
      FileUtils.mkdir_p(tmp.join("app/javascript"))
      File.write(tmp.join("app/javascript/application.js"), <<~JS)
        import { application } from "./application"
        // existing registrations
      JS
    end

    it "registers the reactive controller in application.js (issue #106)" do
      run!
      entrypoint = File.read(tmp.join("app/javascript/application.js"))
      expect(entrypoint).to include('import ReactiveController from "phlex/reactive/reactive_controller"')
      expect(entrypoint).to include('application.register("reactive", ReactiveController)')
    end
  end

  context "without a Stimulus entrypoint" do
    it "still writes the initializer and does not crash" do
      expect { run! }.not_to raise_error
      expect(File).to exist(tmp.join("config/initializers/phlex_reactive.rb"))
    end
  end

  it "ends the output telling the user to run the doctor (issue #106)" do
    expect { run! }.to output(/phlex_reactive:doctor/).to_stdout
  end
end
