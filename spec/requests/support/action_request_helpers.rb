# frozen_string_literal: true

# Shared helpers for the request suite (issue #40). Every request spec mints a
# signed identity token and POSTs it to the action endpoint exactly as a
# component would. These two helpers were copy-pasted across the suite; they now
# live here and are mixed into `type: :request` examples via rails_helper.rb.
#
# `post_multipart` (the #34 file path) stays LOCAL to file_params_spec.rb — it
# sends multipart FormData, not a JSON body, so it doesn't belong in this shared
# JSON helper.
module ActionRequestHelpers
  # Mint a token exactly as a component would, using the app's verifier.
  def token_for(klass, payload = {})
    Phlex::Reactive.sign(payload.merge("c" => klass.name))
  end

  # POST a reactive action as a JSON body (token + act + params), the encoding
  # the client uses when no file input is present.
  def post_action(klass, act:, payload: {}, params: {})
    post "/reactive/actions",
      params: { token: token_for(klass, payload), act:, params: }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }
  end
end
