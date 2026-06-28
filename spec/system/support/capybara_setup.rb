# frozen_string_literal: true

# The browser suite runs under TWO real servers so a reactive round trip is
# proven transport-agnostic: Puma (sync, thread-pool — the default) and Falcon
# (async, fiber-per-request — CAPYBARA_SERVER=falcon). CI runs both in a matrix;
# `rake spec:system_servers` runs both locally. No webrick — it isn't a real
# server, so it never proves anything a deployment cares about.
#
# Capybara ships no built-in :falcon server, so register one: wrap the rack app
# with Protocol::Rack's adapter and run Falcon::Server on an Async reactor bound
# to the host:port Capybara hands us. Capybara runs this block on its own server
# thread and expects it to block, which Falcon::Server#run does.
Capybara.register_server(:falcon) do |app, port, host|
  require "falcon/server"
  require "async"
  require "async/http/endpoint"
  require "protocol/rack"

  endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
  rack_app = Protocol::Rack::Adapter.new(app)

  # Falcon::Server#run already wraps itself in an Async reactor and returns that
  # task; wait on it so this block blocks Capybara's server thread until shutdown.
  Falcon::Server.new(rack_app, endpoint).run.wait
end

Capybara.server = case ENV.fetch("CAPYBARA_SERVER", nil)
                  when "falcon"
                    :falcon
                  else
                    [:puma, { Silent: true }]
                  end

RSpec.configure do
  it.before(:each, type: :system) do
    Capybara.configure do
      it.default_max_wait_time = 5
      it.default_driver = :playwright
      it.javascript_driver = :playwright
      it.save_path = "tmp/capybara"
      it.always_include_port = true
    end

    driven_by(:playwright, screen_size: [1280, 800])
  end

  # Screenshot on failure (best-effort).
  it.after(:each, type: :system) do
    next unless it.exception

    begin
      path = Rails.root.join("..", "..", "tmp", "capybara")
      page.save_screenshot(path.join("failure-#{it.full_description.parameterize}.png").to_s) # rubocop:disable Lint/Debugger
    rescue StandardError
      # ignore screenshot failures
    end
  end
end
