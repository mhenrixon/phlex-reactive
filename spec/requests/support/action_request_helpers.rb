# frozen_string_literal: true

# The gem's own request suite dogfoods the PUBLIC Phlex::Reactive::TestHelpers
# (issue #110) — the honesty check that the shipped helper actually works. The
# legacy names (token_for / post_action) that the suite grew up on (issue #40)
# now thinly delegate to the public API, so every existing request spec exercises
# the public module verbatim.
#
# post_multipart stays LOCAL to file_params_spec.rb (it predates the public
# post_reactive_multipart and asserts a slightly different shape); it too rides
# token_for below, so it goes through the public token path.
module ActionRequestHelpers
  include Phlex::Reactive::TestHelpers

  # Legacy alias: the suite mints class-form tokens as token_for(klass, payload).
  def token_for(klass, payload = {})
    reactive_token_for(klass, payload)
  end

  # Legacy alias: post_action(klass, act:, payload:, params:) -> the public
  # post_reactive_action(klass, act, params:, payload:). The wire (JSON body,
  # action_path, headers) is the public helper's, so the suite proves it.
  def post_action(klass, act:, payload: {}, params: {})
    post_reactive_action(klass, act, params:, payload:)
  end
end
