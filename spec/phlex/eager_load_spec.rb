# frozen_string_literal: true

require "spec_helper"

# Regression guard for the Zeitwerk setup. A host app with
# `config.eager_load = true` (the production default) triggers
# `Zeitwerk::Loader.eager_load_all`, which walks every registered loader —
# including this gem's. If the gem's loader manages files that violate
# Zeitwerk's file→constant rule (e.g. version.rb defining VERSION, or the Rails
# generators whose path/constant scheme is intentionally non-Zeitwerk), eager
# loading raises Zeitwerk::NameError and the host app fails to boot.
#
# The dummy app runs with eager_load = false, so only this explicit check
# exercises the eager-load path.
RSpec.describe "Zeitwerk eager loading" do
  it "eager-loads every loader without a NameError" do
    expect { Zeitwerk::Loader.eager_load_all }.not_to raise_error
  end

  it "still exposes the public constants after eager load" do
    Zeitwerk::Loader.eager_load_all
    expect(defined?(Phlex::Reactive::Streamable)).to eq("constant")
    expect(defined?(Phlex::Reactive::Component)).to eq("constant")
    expect(Phlex::Reactive::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end
end
