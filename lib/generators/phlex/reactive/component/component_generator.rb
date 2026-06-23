# frozen_string_literal: true

require "rails/generators/named_base"

module Phlex
  module Reactive
    module Generators
      # `rails g phlex:reactive:component Counter [actions] [options]`
      #
      # Examples:
      #   rails g phlex:reactive:component Counter increment decrement
      #     → state-backed component with two actions
      #
      #   rails g phlex:reactive:component Todos::Item toggle rename --record=todo
      #     → record-backed component (signed GlobalID) with two actions
      #
      # Generates the component under app/components and a matching spec under
      # spec/components (or test/components for Minitest apps).
      class ComponentGenerator < ::Rails::Generators::NamedBase
        source_root File.expand_path("templates", __dir__)

        argument :actions, type: :array, default: [], banner: "action action"

        class_option :record, type: :string, default: nil,
          desc: "Record-backed component: the init kwarg / GlobalID record name (e.g. --record=todo)"
        class_option :state, type: :array, default: nil,
          desc: "State-backed: instance vars to sign (e.g. --state=count open). Default for record-less."

        def create_component
          @component_path = File.join("app/components", class_path, "#{file_name}.rb")
          template "component.rb.erb", File.join(destination_root, @component_path)
        end

        def create_spec
          return unless defined_rspec?

          @spec_path = File.join("spec/components", class_path, "#{file_name}_spec.rb")
          template "component_spec.rb.erb", File.join(destination_root, @spec_path)
        end

        private

        def record_name
          options[:record]&.to_sym
        end

        def record_backed?
          record_name.present?
        end

        def state_keys
          options[:state] || (record_backed? ? [] : %w[value])
        end

        def action_names
          actions.presence || %w[example_action]
        end

        def defined_rspec?
          File.directory?(File.join(destination_root, "spec"))
        end
      end
    end
  end
end
