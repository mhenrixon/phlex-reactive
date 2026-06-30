# frozen_string_literal: true

module Views
  module Docs
    # A doc page header: an optional eyebrow (kicker), the title, and a lead
    # paragraph. Gives every doc page a consistent masthead.
    #
    #   render Views::Docs::Header.new(title: "Architecture", eyebrow: "Guide") do
    #     plain "A component owns a stable DOM id…"
    #   end
    class Header < Phlex::HTML
      def initialize(title:, eyebrow: nil)
        @title = title
        @eyebrow = eyebrow
      end

      def view_template(&block)
        header(class: 'mb-8 border-b border-base-300 pb-6') do
          div(class: 'mb-2 text-xs font-semibold uppercase tracking-wider text-primary') { @eyebrow } if @eyebrow
          h1(class: 'text-3xl font-bold tracking-tight md:text-4xl') { @title }
          p(class: 'mt-3 text-lg text-base-content/70', &block) if block
        end
      end
    end
  end
end
