# frozen_string_literal: true

# Mint a signed identity token and POST it to the reactive action endpoint
# exactly as a component would — mirrors the gem's own request-spec helper.
module ActionRequestHelpers
  def token_for(klass, payload = {})
    Phlex::Reactive.sign(payload.merge('c' => klass.name))
  end

  def post_action(klass, act:, payload: {}, params: {})
    post '/reactive/actions',
         params: { token: token_for(klass, payload), act:, params: }.to_json,
         headers: { 'Content-Type' => 'application/json', 'Accept' => 'text/vnd.turbo-stream.html' }
  end
end

RSpec.configure do |config|
  config.include ActionRequestHelpers, type: :request
end
