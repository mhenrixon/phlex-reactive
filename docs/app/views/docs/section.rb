# frozen_string_literal: true

module Views
  module Docs
    # A titled doc section with an anchor (so the heading is linkable). Body is the
    # block. Use inside a Page; compose with Prose for the text.
    #
    #   render Views::Docs::Section.new("Signed identity") do
    #     render Views::Docs::Prose.new { p { "…" } }
    #   end
    class Section < Phlex::HTML
      def initialize(title, id: nil)
        @title = title
        @id = id || title.parameterize
      end

      def view_template(&)
        section(id: @id, class: 'mb-10 scroll-mt-20') do
          h2(class: 'group mb-4 text-2xl font-semibold tracking-tight') do
            a(href: "##{@id}", class: 'no-underline') do
              plain @title
              span(class: 'ml-2 text-base-content/30 opacity-0 transition group-hover:opacity-100') { '#' }
            end
          end
          yield
        end
      end
    end
  end
end
