# frozen_string_literal: true

require "capybara-playwright-driver"

HEADLESS = %w[1 true].include?(ENV.fetch("HEADLESS", "true"))

Capybara.register_driver(:playwright) do |app|
  Capybara::Playwright::Driver.new(
    app,
    playwright_cli_executable_path: "./node_modules/.bin/playwright",
    browser_type: :chromium,
    headless: HEADLESS
  )
end
