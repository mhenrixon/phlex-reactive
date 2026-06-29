# frozen_string_literal: true

module Views
  module Docs
    class Show < Phlex::HTML
      include Phlex::Rails::Helpers::Routes

      def initialize(doc:)
        @doc = doc
      end

      def view_template
        render Views::Layout.new(title: @doc.title) do
          nav(class: 'mb-6') do
            a(href: root_path, class: 'link link-hover text-sm opacity-70') { '← Home' }
          end

          render Views::Docs::Markdown.new(@doc.body)
        end
      end
    end
  end
end
