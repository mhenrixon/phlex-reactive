# frozen_string_literal: true

# Integration/request-level helper — boots the dummy Rails app.
ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"

require "spec_helper"
require "rspec/rails"

# Build the in-memory schema once for the suite.
ActiveRecord::Schema.verbose = false
load Rails.root.join("db/schema.rb")

# Auto-load request-spec support modules (mirrors system_helper.rb's
# system/support autoload). Holds the shared token_for / post_action helpers.
Dir[File.join(__dir__, "requests/support/**/*.rb")].each { require it }

RSpec.configure do
  it.infer_spec_type_from_file_location!
  it.use_transactional_fixtures = true

  # fixture_file_upload (multipart upload specs, issue #34) resolves files here.
  it.file_fixture_path = File.expand_path("fixtures/files", __dir__)
  it.include ActionDispatch::TestProcess::FixtureFile

  # Shared request helpers (token_for / post_action) — issue #40.
  it.include ActionRequestHelpers, type: :request

  # In the dummy app the verifier comes from secret_key_base; align the test
  # verifier so tokens minted in specs verify against the running app.
  it.before(:suite) do
    Phlex::Reactive.instance_variable_set(:@verifier, nil) # use Rails default
  end
end
