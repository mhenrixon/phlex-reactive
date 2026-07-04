# frozen_string_literal: true

module Components
  module Diagrams
    # The landing hero picture: three different triggers — a click, a form
    # change, a background broadcast — all converge on ONE re-render unit (the
    # component that owns a stable #id). The single idea the whole library is
    # built on, in one glance. Theme-aware via daisyUI CSS variables.
    class MentalModel < Components::Base
      TRIGGERS = [
        ['click', 'an action'],
        ['input', 'a form change'],
        ['broadcast', 'another tab']
      ].freeze

      def view_template
        svg(
          viewbox: '0 0 640 260',
          width: '100%',
          xmlns: 'http://www.w3.org/2000/svg',
          class: 'text-base-content w-full max-w-2xl',
          font_family: 'ui-sans-serif, system-ui, sans-serif',
          aria: { label: 'A click, an input, and a broadcast all converge on one ' \
                         'component that re-renders into its own id.' },
          role: 'img'
        ) do |s|
          s.defs do
            s.marker(id: 'mmarrow', viewbox: '0 0 10 10', refx: '8', refy: '5',
                     markerwidth: '6', markerheight: '6', orient: 'auto-start-reverse') do
              s.path(d: 'M0 0 L10 5 L0 10 z', fill: 'var(--color-primary)')
            end
            s.linearGradient(id: 'mmcore', x1: '0', y1: '0', x2: '1', y2: '1') do
              s.stop(offset: '0', stop_color: 'var(--color-primary)')
              s.stop(offset: '1', stop_color: 'var(--color-accent)')
            end
          end

          # the three triggers, left
          TRIGGERS.each_with_index do |(title, sub), i|
            y = 40 + (i * 80)
            s.rect(x: 20, y: y, width: 170, height: 56, rx: '12',
                   fill: 'var(--color-base-100)', stroke: 'var(--color-base-300)', stroke_width: '1.5')
            s.text(x: 105, y: y + 26, text_anchor: 'middle', font_size: '15',
                   font_weight: '700', fill: 'currentColor') { title }
            s.text(x: 105, y: y + 44, text_anchor: 'middle', font_size: '11.5',
                   fill: 'var(--color-base-content)', opacity: '0.6') { sub }
            # arrow to the core
            s.path(d: "M190 #{y + 28} C280 #{y + 28} 300 130 360 130",
                   fill: 'none', stroke: 'var(--color-primary)', stroke_width: '2',
                   opacity: '0.85', marker_end: 'url(#mmarrow)')
          end

          # the ONE re-render unit, center-right
          s.rect(x: 366, y: 78, width: 250, height: 104, rx: '18',
                 fill: 'url(#mmcore)', opacity: '0.14')
          s.rect(x: 366, y: 78, width: 250, height: 104, rx: '18',
                 fill: 'none', stroke: 'url(#mmcore)', stroke_width: '2')
          s.text(x: 491, y: 116, text_anchor: 'middle', font_size: '18',
                 font_weight: '800', fill: 'currentColor') { 'one component' }
          s.text(x: 491, y: 140, text_anchor: 'middle', font_size: '13',
                 font_family: 'ui-monospace, monospace', fill: 'var(--color-primary)') do
            'render → #id'
          end
          s.text(x: 491, y: 162, text_anchor: 'middle', font_size: '11.5',
                 fill: 'var(--color-base-content)', opacity: '0.6') { 'signed identity, not state' }
        end
      end
    end
  end
end
