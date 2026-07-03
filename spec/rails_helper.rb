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

  # The public test helpers (issue #110): the no-HTTP run_reactive driver, token
  # minting, and the have_reactive_* matchers, mixed in exactly as a downstream
  # app would (this IS the shipped setup). The HTTP helpers
  # (post_reactive_action / post_reactive_multipart) need integration `post`, so
  # they belong to request examples.
  it.include Phlex::Reactive::TestHelpers
  it.include Phlex::Reactive::TestHelpers, type: :request

  # The gem's legacy request helpers (token_for / post_action, issue #40) now
  # delegate to the public module — dogfooding the shipped API.
  it.include ActionRequestHelpers, type: :request

  # In the dummy app the verifier comes from secret_key_base; align the test
  # verifier so tokens minted in specs verify against the running app.
  it.before(:suite) do
    Phlex::Reactive.instance_variable_set(:@verifier, nil) # use Rails default
  end
end
