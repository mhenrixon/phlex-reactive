# frozen_string_literal: true

# Unit-level helper — no Rails. Loads the library and provides a deterministic
# verifier so identity tokens can be signed/verified without a Rails app.
require "active_support"
require "active_support/core_ext"
require "globalid"
require "phlex/reactive"

GlobalID.app = "phlex-reactive-test"

Phlex::Reactive.verifier = ActiveSupport::MessageVerifier.new("phlex-reactive-test-secret")

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.order = :random
  Kernel.srand config.seed
end
