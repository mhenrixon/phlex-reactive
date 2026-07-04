# frozen_string_literal: true

module Components
  module Diagrams
    # Broadcast fan-out: ONE render on the server, one payload, pushed over the
    # transport to every subscriber of a stream — each tab morphs the same
    # component #id. The actor is excluded (they already got the action's reply).
    # Theme-aware via daisyUI CSS variables.
    class BroadcastFanout < Components::Base
      VIEWERS = ["Tab A", "Tab B", "Tab C", "Tab D"].freeze

      def view_template
        render Figure.new(
          caption: "One render, one payload — the transport fans it to every " \
                   "subscriber; the actor is excluded from the echo.",
          label: "Broadcast fan-out: a model change renders once and the transport " \
                 "delivers the identical stream to every subscribed tab."
        ) do
          svg(
            viewbox: "0 0 900 320",
            width: "100%",
            xmlns: "http://www.w3.org/2000/svg",
            class: "text-base-content",
            font_family: "ui-sans-serif, system-ui, sans-serif"
          ) do |s|
            s.defs do
              s.marker(id: "bfarrow", viewbox: "0 0 10 10", refx: "8", refy: "5",
                       markerwidth: "7", markerheight: "7", orient: "auto-start-reverse") do
                s.path(d: "M0 0 L10 5 L0 10 z", fill: "var(--color-primary)")
              end
            end

            # source: model change -> render ONCE
            s.rect(x: 30, y: 96, width: 170, height: 60, rx: "12",
                   fill: "var(--color-base-100)", stroke: "var(--color-base-300)", stroke_width: "1.5")
            text_c(s, 115, 122, "model change", weight: "700", size: "15")
            text_c(s, 115, 142, "after_commit / job", size: "11.5", opacity: "0.6")

            s.rect(x: 250, y: 86, width: 200, height: 80, rx: "12",
                   fill: "var(--color-primary)", opacity: "0.12")
            s.rect(x: 250, y: 86, width: 200, height: 80, rx: "12",
                   fill: "none", stroke: "var(--color-primary)", stroke_width: "1.5")
            text_c(s, 350, 116, "render ONCE", color: "var(--color-primary)", weight: "700", size: "16")
            text_c(s, 350, 138, "broadcast_replace_to", size: "12", opacity: "0.75")
            text_c(s, 350, 154, "→ one shared payload", size: "11.5", opacity: "0.6")

            s.path(d: "M200 126 H250", fill: "none", stroke: "var(--color-primary)",
                   stroke_width: "2", marker_end: "url(#bfarrow)")

            # the transport hub
            s.circle(cx: 520, cy: 126, r: "8", fill: "var(--color-primary)")
            text_c(s, 520, 100, "transport", size: "11", opacity: "0.6")
            text_c(s, 520, 164, "Cable / pgbus", size: "10.5", opacity: "0.5")
            s.path(d: "M450 126 H508", fill: "none", stroke: "var(--color-primary)", stroke_width: "2")

            # fan out to every subscriber
            VIEWERS.each_with_index do |name, i|
              y = 40 + i * 66
              actor = (i == 1)
              stroke = actor ? "var(--color-base-300)" : "var(--color-primary)"
              s.path(d: "M528 126 C610 126 640 #{y + 22} 700 #{y + 22}",
                     fill: "none", stroke: stroke, stroke_width: "2",
                     stroke_dasharray: (actor ? "3 5" : nil),
                     opacity: (actor ? "0.5" : "1"),
                     marker_end: (actor ? nil : "url(#bfarrow)"))
              s.rect(x: 700, y: y, width: 180, height: 44, rx: "10",
                     fill: "var(--color-base-100)", stroke: stroke, stroke_width: "1.5",
                     opacity: (actor ? "0.55" : "1"))
              text_c(s, 776, y + 20, name, size: "13", weight: "600")
              sub = actor ? "actor — excluded" : "morph #id"
              text_c(s, 776, y + 35, sub, size: "10.5",
                     opacity: "0.6", color: (actor ? "var(--color-base-content)" : "var(--color-primary)"))
            end
          end
        end
      end

      private

      def text_c(s, x, y, str, size: "13", weight: "400", opacity: "1", color: "currentColor")
        s.text(x: x, y: y, text_anchor: "middle", font_size: size,
               font_weight: weight, fill: color, opacity: opacity) { str }
      end
    end
  end
end
