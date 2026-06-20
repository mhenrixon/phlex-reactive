# frozen_string_literal: true

require "minitest/autorun"
require "active_support"
require "active_support/core_ext"
require "phlex/reactive"

# Tokens are signed; provide a deterministic verifier for tests so we don't
# need a Rails app.
Phlex::Reactive.verifier = ActiveSupport::MessageVerifier.new("phlex-reactive-test-secret")
