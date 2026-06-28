# frozen_string_literal: true

require "rails/generators/base"

module Phlex
  module Reactive
    module Generators
      # `rails g phlex:reactive:install`
      #
      # One-command setup for phlex-reactive:
      #   * registers the generic `reactive` Stimulus controller (eagerly)
      #   * writes a config initializer with the common options commented out
      #
      # The action endpoint and client auto-pin are provided by the engine, so
      # this generator only wires the bits that live in the host app.
      class InstallGenerator < ::Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        IMPORT_LINE = 'import ReactiveController from "phlex/reactive/reactive_controller"'
        REGISTER_LINE = 'application.register("reactive", ReactiveController)'

        def create_initializer
          template "phlex_reactive.rb.erb", "config/initializers/phlex_reactive.rb"
        end

        # Register the controller eagerly in the Stimulus entrypoint. Eager (not
        # lazy) so a click immediately after page load is never missed.
        def register_stimulus_controller
          index = stimulus_index_path

          unless index
            say_status :skip, "no Stimulus controllers entrypoint found — register manually:\n    " \
                              "#{IMPORT_LINE}\n    #{REGISTER_LINE}", :yellow
            return
          end

          if File.read(index).include?(REGISTER_LINE)
            say_status :identical, relative(index), :blue
            return
          end

          inject_into_file index, after: %r{import \{ application \} from ["']controllers/application["']\n} do
            "#{IMPORT_LINE}\n#{REGISTER_LINE}\n"
          end

          # Fallback: if the standard import line wasn't found, append both lines.
          return if File.read(index).include?(REGISTER_LINE)

          append_to_file index, "\n#{IMPORT_LINE}\n#{REGISTER_LINE}\n"
        end

        def show_post_install
          say_status :info, "phlex-reactive installed. Include the mixins in a component:", :green
          say <<~MSG

            class Counter < ApplicationComponent
              include Phlex::Reactive::Streamable
              include Phlex::Reactive::Component
              # ... reactive_state / reactive_record, action :name, on(:name) ...
            end

            Scaffold one with:  rails g phlex:reactive:component Counter
          MSG
        end

        private

        def stimulus_index_path
          %w[
            app/javascript/controllers/index.js
            app/javascript/controllers/application.js
          ].map { File.join(destination_root, it) }.find { File.exist?(it) }
        end

        def relative(path)
          path.sub("#{destination_root}/", "")
        end
      end
    end
  end
end
