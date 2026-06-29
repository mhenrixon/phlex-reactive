# frozen_string_literal: true

require 'commonmarker'

module Views
  module Docs
    # Renders a Markdown string as HTML (GFM + syntax-highlighted code blocks)
    # inside a Tailwind/daisyUI `prose` wrapper. The reference docs are authored in
    # Markdown (single source of truth, ported from the gem's docs/) and rendered
    # here as a first-class Phlex page — no hand-transcription, no prose drift.
    class Markdown < Phlex::HTML
      OPTIONS = { render: { unsafe: false, hardbreaks: false } }.freeze
      PLUGINS = { syntax_highlighter: { theme: 'base16-ocean.dark' } }.freeze

      def initialize(source)
        @source = source
      end

      def view_template
        article(class: 'prose prose-invert max-w-none') do
          raw(safe(Commonmarker.to_html(@source, options: OPTIONS, plugins: PLUGINS))) # rubocop:disable Rails/OutputSafety
        end
      end
    end
  end
end
