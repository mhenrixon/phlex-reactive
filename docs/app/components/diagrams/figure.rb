# frozen_string_literal: true

module Components
  module Diagrams
    # A theme-aware diagram wrapper: a rounded, bordered surface that scrolls
    # horizontally on narrow screens, with an optional caption. The child SVG
    # paints with daisyUI CSS variables (var(--color-*)) + currentColor, so it
    # re-tints with every theme the switcher offers — no per-theme asset.
    class Figure < Components::Base
      def initialize(caption: nil, label: nil)
        @caption = caption
        @label = label
      end

      def view_template(&block)
        figure(class: "not-prose my-6") do
          div(
            class: "overflow-x-auto rounded-box border border-base-300 bg-base-200/40 p-4 sm:p-6",
            role: "img",
            aria: { label: @label || @caption }
          ) do
            div(class: "min-w-[36rem]", &block)
          end
          if @caption
            figcaption(class: "mt-2 text-sm text-base-content/60") { @caption }
          end
        end
      end
    end
  end
end
