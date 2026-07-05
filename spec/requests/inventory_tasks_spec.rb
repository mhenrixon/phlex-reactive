# frozen_string_literal: true

require "rails_helper"
require "rake"

# The `phlex_reactive:actions` and `phlex_reactive:find[query]` rake tasks ship
# in lib/tasks and are auto-loaded by the Rails engine in a host app (issue #168).
# They surface the Inspector's read-only inventory as plain text (FORMAT=json for
# machine consumption), the same no-ANSI posture as the doctor. Here we load the
# .rake file against the booted dummy app and drive each task.
RSpec.describe "phlex_reactive inventory rake tasks" do
  let(:rake) do
    app = Rake::Application.new
    Rake.application = app
    Rake::Task.define_task(:environment) # already booted; the task just depends on it
    load File.expand_path("../../lib/tasks/phlex_reactive.rake", __dir__)
    app
  end

  before { Rails.application.eager_load! }

  after do
    Rake.application = Rake::Application.new
    ENV.delete("FORMAT")
  end

  describe "phlex_reactive:actions" do
    it "is defined" do
      rake
      expect(Rake::Task.task_defined?("phlex_reactive:actions")).to be(true)
    end

    it "prints a plain-text table naming a component and its actions (no ANSI color)" do
      output = capture_stdout { rake["phlex_reactive:actions"].invoke }
      expect(output).to include("CounterComponent")
      expect(output).to include("increment")
      expect(output).not_to match(/\e\[[0-9;]*m/) # no ANSI escapes
    end

    it "shows the declared param schema for an action that takes params" do
      output = capture_stdout { rake["phlex_reactive:actions"].invoke }
      # CounterComponent declares `action :set, params: { count: :integer }`.
      expect(output).to match(/set.*count/m)
    end

    it "emits parseable JSON when FORMAT=json" do
      ENV["FORMAT"] = "json"
      output = capture_stdout { rake["phlex_reactive:actions"].invoke }
      parsed = JSON.parse(output)
      counter = parsed.find { it["component"] == "CounterComponent" }
      expect(counter).not_to be_nil
      action_names = counter["actions"].map { it["name"] }
      expect(action_names).to include("increment", "set")
    end

    it "never leaks a token, secret, or runtime state into the output" do
      ENV["FORMAT"] = "json"
      output = capture_stdout { rake["phlex_reactive:actions"].invoke }
      expect(output).not_to include(Rails.application.secret_key_base)
    end
  end

  describe "phlex_reactive:find[query]" do
    it "is defined" do
      rake
      expect(Rake::Task.task_defined?("phlex_reactive:find")).to be(true)
    end

    it "prints the top match in detail with each action's method definition source" do
      output = capture_stdout { rake["phlex_reactive:find"].invoke("counter") }
      expect(output).to include("CounterComponent")
      # The detail prints the method definition source extracted with Prism.
      expect(output).to include("def increment")
    end

    it "reports no match for an unknown query" do
      output = capture_stdout { rake["phlex_reactive:find"].invoke("zzz_no_such_zzz") }
      expect(output).to match(/no.*match/i)
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
