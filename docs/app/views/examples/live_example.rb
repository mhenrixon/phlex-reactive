# frozen_string_literal: true

module Views
  module Examples
    # A drift-proof inline embed for an example DOC PAGE: render a REAL reactive
    # component live AND show that same component's own source, read live off its
    # file. Because the demo and the code come from ONE class, they can never
    # diverge — the exact drift the docs are meant to warn adopters about.
    #
    # This is the docs-page cousin of Views::Examples::DemoPanel (the CSS-tab
    # panel behind the /demos/* gallery): same "read the source you render"
    # guarantee, but laid out inline for a prose page — the live component in a
    # bordered box, then its source in a highlighted block.
    #
    #   render Views::Examples::LiveExample.new(
    #     component: TodoListComponent.new,
    #     filename: "app/components/todo_list_component.rb"
    #   )
    class LiveExample < Phlex::HTML
      def initialize(component:, filename: nil, source: nil)
        @component = component
        @filename = filename
        @source = source
      end

      def view_template
        div(class: 'not-prose my-6 flex flex-col gap-4') do
          live_demo
          component_source_block
        end
      end

      private

      # The live component, rendered into a bordered box so it reads as "the demo"
      # on a prose page. It self-targets its own #id and round-trips like anywhere.
      def live_demo
        div(class: 'rounded-box border border-base-300 bg-base-100 p-6',
            data: { testid: 'live-example-demo' }) do
          render @component
        end
      end

      def component_source_block
        DocsUI::Code(component_source, lexer: :ruby, filename: @filename)
      end

      # The component's own source. Prefer an explicit `source:` (for a source
      # that isn't a single file — e.g. a trio of collaborating classes), else
      # read the file backing this component's view_template. Falls back to the
      # whole file, matching DemoPanel#component_source.
      def component_source
        return @source if @source

        path = @component.class.instance_method(:view_template).source_location&.first
        path ? File.read(path).strip : '# source unavailable'
      end
    end
  end
end
