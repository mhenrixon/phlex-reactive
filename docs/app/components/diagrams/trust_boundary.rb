# frozen_string_literal: true

module Components
  module Diagrams
    # The signed-identity trust boundary: the DOM carries a MessageVerifier-signed
    # {c, gid}/{c, s} token — identity, never state. Everything a click sends is
    # UNTRUSTED until the endpoint verifies the signature, then re-finds the
    # record server-side, default-denies undeclared actions, coerces params
    # through the schema, and makes YOU authorize. Theme-aware.
    class TrustBoundary < Components::Base
      def view_template
        render Figure.new(
          caption: "The signature proves the token is ours — not that this user " \
                   "may act. The gates run in order; you own authorization.",
          label: "Security trust boundary: an untrusted browser token crosses into " \
                 "the server through verify, re-find, default-deny, coerce, authorize."
        ) do
          svg(
            viewbox: "0 0 900 340",
            width: "100%",
            xmlns: "http://www.w3.org/2000/svg",
            class: "text-base-content",
            font_family: "ui-sans-serif, system-ui, sans-serif"
          ) do |s|
            s.defs do
              s.marker(id: "tbarrow", viewbox: "0 0 10 10", refx: "8", refy: "5",
                       markerwidth: "7", markerheight: "7", orient: "auto-start-reverse") do
                s.path(d: "M0 0 L10 5 L0 10 z", fill: "var(--color-primary)")
              end
            end

            # UNTRUSTED zone (left)
            s.rect(x: 20, y: 30, width: 250, height: 280, rx: "14",
                   fill: "var(--color-warning)", opacity: "0.07")
            s.rect(x: 20, y: 30, width: 250, height: 280, rx: "14",
                   fill: "none", stroke: "var(--color-warning)", stroke_width: "1.5",
                   stroke_dasharray: "6 5")
            zone_label(s, 145, 56, "UNTRUSTED — the browser", "var(--color-warning)")

            token(s)

            # the boundary line
            s.line(x1: 300, y1: 20, x2: 300, y2: 320,
                   stroke: "var(--color-base-content)", stroke_width: "1", opacity: "0.25",
                   stroke_dasharray: "2 4")

            # TRUSTED zone (right): the gate stack
            s.rect(x: 330, y: 30, width: 550, height: 280, rx: "14",
                   fill: "var(--color-success)", opacity: "0.06")
            s.rect(x: 330, y: 30, width: 550, height: 280, rx: "14",
                   fill: "none", stroke: "var(--color-success)", stroke_width: "1.5")
            zone_label(s, 605, 56, "TRUSTED — the endpoint", "var(--color-success)")

            gates = [
              ["verify signature", "tamper → 400", "1"],
              ["re-find the record", "GlobalID::Locator (server)", "2"],
              ["default-deny action", "undeclared → 403", "3"],
              ["coerce params", "schema only — no mass assign", "4"],
              ["authorize! (YOU)", "signature ≠ permission", "5"]
            ]
            gates.each_with_index do |(title, sub, n), i|
              gate(s, y: 76 + i * 46, title: title, sub: sub, n: n, danger: (i == 4))
            end

            # arrow across the boundary
            s.path(d: "M245 150 H360", fill: "none", stroke: "var(--color-primary)",
                   stroke_width: "2", marker_end: "url(#tbarrow)")
            s.text(x: 302, y: 140, text_anchor: "middle", font_size: "11",
                   fill: "var(--color-primary)", opacity: "0.8") { "POST" }
          end
        end
      end

      private

      def zone_label(s, x, y, str, color)
        s.text(x: x, y: y, text_anchor: "middle", font_size: "12.5",
               font_weight: "700", fill: color) { str }
      end

      def token(s)
        s.rect(x: 45, y: 120, width: 200, height: 90, rx: "12",
               fill: "var(--color-base-100)", stroke: "var(--color-warning)", stroke_width: "1.5")
        s.text(x: 145, y: 148, text_anchor: "middle", font_size: "13",
               font_weight: "700", fill: "currentColor") { "signed token" }
        s.text(x: 145, y: 170, text_anchor: "middle", font_size: "12",
               font_family: "ui-monospace, monospace", fill: "var(--color-base-content)",
               opacity: "0.75") { "{ c, gid }  ·  { c, s }" }
        s.text(x: 145, y: 192, text_anchor: "middle", font_size: "11",
               fill: "var(--color-base-content)", opacity: "0.6") { "identity, never state" }
      end

      def gate(s, y:, title:, sub:, n:, danger: false)
        color = danger ? "var(--color-warning)" : "var(--color-success)"
        s.circle(cx: 360, cy: y + 15, r: "11", fill: color, opacity: "0.18")
        s.text(x: 360, y: y + 19, text_anchor: "middle", font_size: "12",
               font_weight: "700", fill: color) { n }
        s.text(x: 384, y: y + 12, font_size: "13.5", font_weight: "600",
               fill: "currentColor") { title }
        s.text(x: 384, y: y + 28, font_size: "11.5",
               fill: "var(--color-base-content)", opacity: "0.6") { sub }
      end
    end
  end
end
