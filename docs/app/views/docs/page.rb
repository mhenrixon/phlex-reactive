# frozen_string_literal: true

module Views
  module Docs
    # The base class for a hand-authored doc page. Subclasses set the title (and
    # optional eyebrow/lead) and implement #content with the page body, composing
    # the doc kit (Section/Prose/Code/Callout). Page renders it inside the site
    # Layout with a consistent masthead.
    #
    #   class Views::Docs::Pages::Architecture < Views::Docs::Page
    #     title "Architecture"
    #     eyebrow "Guide"
    #     def lead = "A component owns a stable DOM id…"
    #     def content
    #       render Views::Docs::Section.new("The mental model") { … }
    #     end
    #   end
    class Page < Phlex::HTML
      include Phlex::Rails::Helpers::Routes

      class << self
        def title(value = nil)
          @title = value if value
          @title
        end

        def eyebrow(value = nil)
          @eyebrow = value if value
          @eyebrow
        end
      end

      def view_template
        render Views::Layout.new(title: self.class.title) do
          nav(class: 'mb-6') do
            a(href: root_path, class: 'link link-hover text-sm opacity-70') { '← Home' }
          end

          render Views::Docs::Header.new(title: self.class.title, eyebrow: self.class.eyebrow) do
            plain lead if lead
          end

          content
        end
      end

      # Override in subclasses for the lead paragraph (optional).
      def lead = nil

      # Override in subclasses with the page body.
      def content
        raise NotImplementedError, "#{self.class} must implement #content"
      end
    end
  end
end
