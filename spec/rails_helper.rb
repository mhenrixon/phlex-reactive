# frozen_string_literal: true

# Integration/request-level helper — boots the dummy Rails app.
ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"

require "spec_helper"
require "rspec/rails"

# Build the in-memory schema once for the suite.
ActiveRecord::Schema.verbose = false
load Rails.root.join("db/schema.rb")

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.use_transactional_fixtures = true

  # In the dummy app the verifier comes from secret_key_base; align the test
  # verifier so tokens minted in specs verify against the running app.
  config.before(:suite) do
    Phlex::Reactive.instance_variable_set(:@verifier, nil) # use Rails default
  end
end
