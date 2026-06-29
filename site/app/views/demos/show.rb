# frozen_string_literal: true

module Views
  module Demos
    class Show < Phlex::HTML
      include Phlex::Rails::Helpers::Routes

      def initialize(demo:)
        @demo = demo
      end

      def view_template
        render Views::Layout.new(title: @demo.title) do
          nav(class: 'mb-6') do
            a(href: root_path, class: 'link link-hover text-sm opacity-70') { '← All demos' }
          end

          header(class: 'mb-6') do
            h1(class: 'text-3xl font-bold mb-2') { @demo.title }
            p(class: 'opacity-70') { @demo.blurb }
          end

          render Views::Examples::DemoPanel.new(
            component: @demo.component_class.new,
            call_site: @demo.call_site
          )
        end
      end
    end
  end
end
