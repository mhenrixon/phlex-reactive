# frozen_string_literal: true

Rails.application.configure do
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.allow_forgery_protection = false
  config.secret_key_base = "dev_secret_key_base_for_phlex_reactive_dummy"
end
