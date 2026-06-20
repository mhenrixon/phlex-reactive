# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "turbo-rails"
require "phlex-rails"

Bundler.require(*Rails.groups)
require "phlex/reactive"
# Ensure the engine loads even if phlex/reactive was required before Rails
# (e.g. unit specs using spec_helper running before system specs).
require "phlex/reactive/engine"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.hosts.clear
    config.active_job.queue_adapter = :test

    # The dummy app's components/views live under app/.
    config.autoload_paths << root.join("app/components").to_s
  end
end
