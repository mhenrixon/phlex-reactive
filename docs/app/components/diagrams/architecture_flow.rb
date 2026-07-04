# frozen_string_literal: true

module Components
  module Diagrams
    # The reactive round trip, as one picture: a browser event POSTs the signed
    # token to the endpoint, which verifies → rebuilds → runs the action →
    # streams the reply back into the SAME component #id; a model change fans the
    # identical render out to OTHER tabs over the transport. Theme-aware: every
    # colour is a daisyUI CSS variable, so it re-tints with the theme switcher.
    class ArchitectureFlow < Components::Base
      def view_template
        render Figure.new(
          caption: 'One re-render unit: a click and a broadcast both resolve to ' \
                   '“render this component into that id.”',
          label: 'Architecture flow: browser event to endpoint to action to reply, ' \
                 'with a broadcast fanning the same render to other tabs.'
        ) do
          svg(
            viewbox: '0 0 920 370',
            width: '100%',
            xmlns: 'http://www.w3.org/2000/svg',
            class: 'text-base-content',
            font_family: 'ui-sans-serif, system-ui, sans-serif'
          ) do |s|
            defs_block(s)
            actor_tab(s)
            endpoint_pipeline(s)
            reply_arrow(s)
            transport_fanout(s)
          end
        end
      end

      private

      def defs_block(s)
        s.defs do
          s.marker(id: 'arrow', viewbox: '0 0 10 10', refx: '8', refy: '5',
                   markerwidth: '7', markerheight: '7', orient: 'auto-start-reverse') do
            s.path(d: 'M0 0 L10 5 L0 10 z', fill: 'var(--color-primary)')
          end
          s.marker(id: 'arrow-accent', viewbox: '0 0 10 10', refx: '8', refy: '5',
                   markerwidth: '7', markerheight: '7', orient: 'auto-start-reverse') do
            s.path(d: 'M0 0 L10 5 L0 10 z', fill: 'var(--color-accent)')
          end
        end
      end

      # A rounded box with a title + subtitle. Fill/stroke are daisyUI vars.
      def node(s, x:, y:, w:, h:, title:, subtitle: nil, fill: 'var(--color-base-100)', stroke: 'var(--color-base-300)')
        s.rect(x: x, y: y, width: w, height: h, rx: '12',
               fill: fill, stroke: stroke, stroke_width: '1.5')
        s.text(x: x + (w / 2), y: subtitle ? y + (h / 2) - 6 : y + (h / 2) + 5,
               text_anchor: 'middle', font_size: '16', font_weight: '700',
               fill: 'currentColor') { title }
        return unless subtitle

        s.text(x: x + (w / 2), y: y + (h / 2) + 15, text_anchor: 'middle',
               font_size: '12', fill: 'var(--color-base-content)', opacity: '0.6') { subtitle }
      end

      def link(s, d, marker: 'arrow', color: 'var(--color-primary)', dash: nil)
        attrs = { d: d, fill: 'none', stroke: color, stroke_width: '2',
                  marker_end: "url(##{marker})" }
        attrs[:stroke_dasharray] = dash if dash
        s.path(**attrs)
      end

      def label(s, x, y, text, color: 'var(--color-base-content)', opacity: '0.7', anchor: 'middle')
        s.text(x: x, y: y, text_anchor: anchor, font_size: '12',
               fill: color, opacity: opacity) { text }
      end

      def actor_tab(s)
        node(s, x: 20, y: 130, w: 150, h: 70,
                title: 'Browser', subtitle: 'click · input',
                fill: 'var(--color-base-100)')
        label(s, 245, 118, 'POST /reactive/actions', color: 'var(--color-primary)', opacity: '0.9')
        label(s, 245, 134, 'signed token + action', opacity: '0.6')
        link(s, 'M170 155 H330')
      end

      def endpoint_pipeline(s)
        # the endpoint pipeline: verify -> rebuild -> run
        node(s, x: 330, y: 60, w: 250, h: 210,
                title: '', fill: 'var(--color-base-200)', stroke: 'var(--color-primary)')
        label(s, 455, 82, 'Endpoint', color: 'var(--color-primary)', opacity: '0.95')
        step(s, x: 350, y: 96, n: '1', text: 'verify token — no client state trusted')
        step(s, x: 350, y: 140, n: '2', text: 'rebuild component — re-find record')
        step(s, x: 350, y: 184, n: '3', text: 'run whitelisted action (default-deny)')
        # the returned Response
        node(s, x: 350, y: 224, w: 210, h: 34,
                title: '→ reply.replace / morph / …', fill: 'var(--color-base-100)',
                stroke: 'var(--color-base-300)')
      end

      def step(s, x:, y:, n:, text:)
        s.circle(cx: x + 12, cy: y + 12, r: '11',
                 fill: 'var(--color-primary)', opacity: '0.15')
        s.text(x: x + 12, y: y + 16, text_anchor: 'middle', font_size: '12',
               font_weight: '700', fill: 'var(--color-primary)') { n }
        s.text(x: x + 32, y: y + 16, font_size: '12.5', fill: 'currentColor') { text }
      end

      def reply_arrow(s)
        # reply streams back into the SAME component id
        node(s, x: 710, y: 56, w: 190, h: 80,
                title: 'Actor’s tab', subtitle: 'replace #id in place',
                fill: 'var(--color-base-100)', stroke: 'var(--color-primary)')
        link(s, 'M580 110 C650 110 645 96 710 96')
        label(s, 648, 84, 'turbo-stream reply', opacity: '0.6')
      end

      def transport_fanout(s)
        # a model change fans the same render out over the transport
        node(s, x: 330, y: 300, w: 250, h: 44,
                title: 'broadcast_*_to — same render',
                fill: 'var(--color-accent)', stroke: 'var(--color-accent)')
        # accent boxes ~ other viewers, each getting the identical render
        2.times do |i|
          y = 176 + (i * 60)
          s.rect(x: 710, y: y, width: 190, height: 44, rx: '10',
                 fill: 'var(--color-base-100)', stroke: 'var(--color-accent)', stroke_width: '1.5')
          s.text(x: 805, y: y + 27, text_anchor: 'middle', font_size: '13',
                 fill: 'currentColor') { "Other tab #{i + 1}" }
          link(s, "M580 322 C648 322 645 #{y + 22} 710 #{y + 22}",
               marker: 'arrow-accent', color: 'var(--color-accent)', dash: '5 4')
        end
        link(s, 'M455 270 V300', color: 'var(--color-accent)', marker: 'arrow-accent')
        label(s, 620, 316, 'over the transport (Cable / pgbus)', color: 'var(--color-accent)', opacity: '0.85')
      end
    end
  end
end
