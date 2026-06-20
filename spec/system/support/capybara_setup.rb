# frozen_string_literal: true

# Default to Puma (matches CI). Set CAPYBARA_SERVER=webrick locally if your
# Ruby/Puma native extensions are mismatched and Puma's reactor segfaults.
case ENV["CAPYBARA_SERVER"]
when "webrick"
  require "webrick"
  Capybara.server = :webrick
else
  Capybara.server = :puma, { Silent: true }
end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    Capybara.configure do |c|
      c.default_max_wait_time = 5
      c.default_driver = :playwright
      c.javascript_driver = :playwright
      c.save_path = "tmp/capybara"
      c.always_include_port = true
    end

    driven_by(:playwright, screen_size: [1280, 800])
  end

  # Screenshot on failure (best-effort).
  config.after(:each, type: :system) do |example|
    next unless example.exception

    begin
      path = Rails.root.join("..", "..", "tmp", "capybara")
      page.save_screenshot(path.join("failure-#{example.full_description.parameterize}.png").to_s)
    rescue StandardError
      # ignore screenshot failures
    end
  end
end
