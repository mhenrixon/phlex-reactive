# frozen_string_literal: true

module Views
  module Docs
    # A callout box (note / warning / tip) for the docs. daisyUI alert styling +
    # a lucide icon per level.
    #
    #   render Views::Docs::Callout.new(:warning) { "Never trust client input." }
    class Callout < Phlex::HTML
      LEVELS = {
        note: { klass: 'alert-info', icon: 'info' },
        tip: { klass: 'alert-success', icon: 'lightbulb' },
        warning: { klass: 'alert-warning', icon: 'triangle-alert' }
      }.freeze

      def initialize(level = :note, title: nil)
        @config = LEVELS.fetch(level, LEVELS[:note])
        @title = title
      end

      def view_template(&)
        div(class: "not-prose alert #{@config[:klass]} my-4 items-start", role: 'note') do
          render Views::Icon.new(@config[:icon], class: 'size-5 shrink-0')
          div do
            div(class: 'font-semibold') { @title } if @title
            div(class: 'text-sm', &)
          end
        end
      end
    end
  end
end
