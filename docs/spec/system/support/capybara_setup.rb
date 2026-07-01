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

# The browser suite also runs at several viewport widths so responsive layout
# regressions (a sidebar/TOC that looks fine on desktop but breaks on a phone)
# are caught. Pick with CAPYBARA_SCREEN (default desktop); CI runs the matrix,
# and `rake spec:system_screens` runs all three locally.
SCREEN_SIZES = {
  'mobile' => [390, 844],   # iPhone 12/13/14
  'tablet' => [820, 1180],  # iPad Air
  'desktop' => [1280, 800]
}.freeze

CAPYBARA_SCREEN = ENV.fetch('CAPYBARA_SCREEN', 'desktop')
CAPYBARA_SCREEN_SIZE = SCREEN_SIZES.fetch(CAPYBARA_SCREEN) do
  raise "CAPYBARA_SCREEN must be one of #{SCREEN_SIZES.keys.join(', ')} (got #{CAPYBARA_SCREEN.inspect})"
end

RSpec.configure do |config|
  # Some specs assert desktop-only layout (the sticky panel TOC is lg:block; the
  # sidebar is an always-open drawer). Skip them when running a small viewport so
  # the matrix doesn't produce false failures — responsive behavior at those
  # widths is asserted by spec/system/responsive_spec.rb instead.
  config.filter_run_excluding(:desktop_only) unless CAPYBARA_SCREEN == 'desktop'

  config.before(:each, type: :system) do
    Capybara.configure do |c|
      c.default_max_wait_time = 5
      c.default_driver = :playwright
      c.javascript_driver = :playwright
      c.always_include_port = true
    end

    driven_by(:playwright, screen_size: CAPYBARA_SCREEN_SIZE)
  end
end
