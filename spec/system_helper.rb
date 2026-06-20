# frozen_string_literal: true

# System-test helper — boots the dummy app and Capybara + Playwright.
require "rails_helper"
require "capybara/rspec"

Dir[File.join(__dir__, "system/support/**/*.rb")].each { |f| require f }
