# frozen_string_literal: true

# Boots the site app + Capybara + Playwright for the browser suite.
require 'rails_helper'
require 'capybara/rspec'

Dir[File.join(__dir__, 'system/support/**/*.rb')].each { require it }
