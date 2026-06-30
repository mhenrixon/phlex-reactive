# frozen_string_literal: true

require 'method_source'

module Views
  module Examples
    # The code-alongside panel for one live demo, shown three ways in CSS-only
    # daisyUI tabs (no JS):
    #   • Demo            — the live reactive component (renders + round-trips)
    #   • Call-site       — how a host mounts it (a small source snippet)
    #   • Component        — the component's own .rb (the reactive DSL itself)
    #
    # Single source of truth: the same `component` instance is rendered live AND
    # its class file is read for the Component tab, so code and demo never drift.
    class DemoPanel < Phlex::HTML
      def initialize(component:, call_site:)
        @component = component
        @call_site = call_site
      end

      def view_template
        div(class: 'tabs tabs-lifted', role: 'tablist', data: { testid: 'demo-panel' }) do
          tab(name: 'Demo', checked: true, testid: 'tab-demo') { live_demo }
          tab(name: 'Call-site', testid: 'tab-call-site') do
            render Views::Examples::Code.new(@call_site, lexer: :ruby)
          end
          tab(name: 'Component', testid: 'tab-component') do
            render Views::Examples::Code.new(component_source, lexer: :ruby)
          end
        end
      end

      private

      # One radio + one content panel per tab. Same `name:` groups them so only
      # one shows; `checked` opens the Demo tab first.
      def tab(name:, testid:, checked: false, &content)
        input(type: 'radio', name: 'demo_tabs', role: 'tab',
              class: 'tab', aria_label: name, checked: checked,
              data: { testid: testid })
        div(role: 'tabpanel', class: 'tab-content border-base-300 bg-base-100 p-4',
            data: { testid: "#{testid}-panel" }, &content)
      end

      def live_demo
        div(class: 'rounded-box border border-base-300 p-6', data: { testid: 'live-demo' }) do
          render @component
        end
      end

      # The component's own source file, read via method_source off its
      # view_template location. Falls back to the whole file.
      def component_source
        path = @component.class.instance_method(:view_template).source_location&.first
        path ? File.read(path).strip : '# source unavailable'
      end
    end
  end
end
