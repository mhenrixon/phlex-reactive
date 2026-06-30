# frozen_string_literal: true

# The browser suite runs under TWO real servers so a reactive round trip is
# proven transport-agnostic: Puma (sync, thread-pool — the default) and Falcon
# (async, fiber-per-request — CAPYBARA_SERVER=falcon). Mirrors the gem's own
# spec/dummy setup. No webrick — it isn't a real server.
#
# Capybara ships no built-in :falcon server, so register one: wrap the rack app
# with Protocol::Rack's adapter and run Falcon::Server on an Async reactor bound
# to the host:port Capybara hands us.
Capybara.register_server(:falcon) do |app, port, host|
  require 'falcon/server'
  require 'async'
  require 'async/http/endpoint'
  require 'protocol/rack'

  endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
  rack_app = Protocol::Rack::Adapter.new(app)
  Falcon::Server.new(rack_app, endpoint).run.wait
end

Capybara.server = case ENV.fetch('CAPYBARA_SERVER', nil)
                  when 'falcon'
                    :falcon
                  else
                    [:puma, { Silent: true }]
                  end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    Capybara.configure do |c|
      c.default_max_wait_time = 5
      c.default_driver = :playwright
      c.javascript_driver = :playwright
      c.always_include_port = true
    end

    driven_by(:playwright, screen_size: [1280, 800])
  end
end
