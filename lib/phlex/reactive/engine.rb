# frozen_string_literal: true

require "rails/engine"

module Phlex
  module Reactive
    # Rails engine: mounts the action endpoint, makes the client runtime
    # available to the asset pipeline, and auto-pins it for importmap apps so
    # `phlex-reactive` works with zero manual wiring on a standard Rails+Phlex
    # app. (Configurable — see config/ options on Phlex::Reactive.)
    class Engine < ::Rails::Engine
      isolate_namespace Phlex::Reactive

      # Mount POST /reactive/actions -> Phlex::Reactive::ActionsController#create.
      # Apps can change the path with Phlex::Reactive.action_path before boot.
      initializer "phlex_reactive.routes" do |app|
        app.routes.append do
          post Phlex::Reactive.action_path, to: "phlex/reactive/actions#create", as: :phlex_reactive_action
        end
      end

      # Make reactive_controller.js available to Propshaft/Sprockets so it can
      # be included via the asset pipeline or pinned in importmap.
      initializer "phlex_reactive.assets" do |app|
        if app.config.respond_to?(:assets)
          app.config.assets.paths << root.join("app/javascript").to_s
          app.config.assets.precompile += %w[phlex/reactive/reactive_controller.js]
        end
      end

      # Auto-pin the client controller for importmap apps so it loads without
      # manual configuration. Apps that don't use importmap include it via the
      # asset pipeline instead (see README).
      initializer "phlex_reactive.importmap", after: "importmap" do |app|
        if defined?(::Importmap::Map) && app.respond_to?(:importmap)
          app.importmap.pin(
            "phlex/reactive/reactive_controller",
            to: "phlex/reactive/reactive_controller.js",
            preload: true
          )
        end
      end

      # Boot-time guard (issue #26): warn if the action path doesn't resolve to
      # the gem controller. Runs after_initialize so the host's full route set
      # (including a bottom-of-file catch-all that would shadow our appended
      # route) is drawn. Turns the opaque "every reactive POST 404s" failure into
      # a one-line log pointing at the cause. No-op when the route is fine.
      config.after_initialize do
        Phlex::Reactive.warn_unless_action_route_mounted!
      end
    end
  end
end
