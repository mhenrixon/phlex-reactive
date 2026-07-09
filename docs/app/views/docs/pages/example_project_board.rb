# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleProjectBoard < DocsUI::Page
        title 'Example: Project board (the kanban flagship)'
        eyebrow 'Examples'
        description 'Build a live kanban board in reactive Phlex: cards move across lanes with ' \
                    'enter/exit effects, live count badges in every open tab, inline rename, and ' \
                    'a confirm-gated archive.'

        def lead
          'One shared board, three lanes. A move is one reply — the row animates out of its lane, ' \
            'into the next, and every count badge repaints — live in every open tab, with no ' \
            'Stimulus controller and no hand-picked Turbo target.'
        end

        def content
          try_it
          whats_here
          the_move
          the_row
          live_counts
          notes
        end

        private

        def try_it
          DocsUI::Section('Try it') do
            md <<~MD
              A real kanban. Move a card with **← →** and watch it animate out of
              one lane and into the next (pick a style — `random` is the fun one).
              Rename a card inline and press **Enter** — the morph keeps your caret.
              **×** archives through a confirm gate and hides the card optimistically.
              Open this page in a second tab: every move, add, rename, and archive
              arrives there live, count badges included.
            MD
            render Views::Examples::LatencyToggle.new(delay_ms: 700)
            render Views::Examples::LiveExample.new(
              component: ProjectBoardComponent.new,
              filename: 'app/components/project_board_component.rb'
            )
          end
        end

        def whats_here
          DocsUI::Section('Every feature, in one board') do
            md <<~MD
              | Feature | Where |
              |---|---|
              | **Effects** — declared enter/exit/update on the row, per-call override from the style picker | the move / the picker |
              | **Nested reactive roots** — each card is its own root inside the board (its rename input stays its own) | the row |
              | **Record + state identity** — the card's GlobalID AND the picked style in one signed token | the row |
              | **`reply.remove(...).stream(...).js(...)`** — one reply moves the card and repaints every badge | `move` |
              | **Live peer counts** — `broadcast_to(js:)` text ops keep every tab's badges honest | every mutation |
              | **Inline rename + morph** — Enter saves; focus and caret survive | the row |
              | **`confirm:` + optimistic hide** — archive gates, then hides in the same gesture | the row |
              | **Per-lane composers** — `busy:` dedupes, a blank title gets an error flash | the board |
              | **CSS `:empty` lanes** — the placeholder needs zero bookkeeping on either path | the lane list |
            MD
          end
        end

        def the_move
          DocsUI::Section('The move — one reply, three streams') do
            md <<~MD
              A move is the whole mental model in one action: the row removes
              itself (its **exit effect runs before the element leaves**), a
              fresh-token render appends into the new lane (wearing its **enter
              effect**), and a `reactive:js` text-op stream repaints all three
              count badges from server truth. The same delta broadcasts to peers
              with the actor's echo excluded:

              ```ruby
              def move(to:)
                return reply.morph unless Card::LANES.include?(to) && to != @card.lane

                @card.update!(lane: to, position: Card.next_position(to))
                broadcast_move
                reply.remove(effect: picked_effect)
                     .stream(self.class.append(target: ProjectBoardComponent.lane_target(to),
                                               model: @card, style: @style, effect: picked_effect))
                     .js(ProjectBoardComponent.count_ops)
              end
              ```

              `picked_effect` is the style picker's choice, signed into the row's
              own state — `default` defers to the row's declared effects, anything
              else overrides **per call** (the issue #215 three-level precedence,
              live).
            MD
          end
        end

        def the_row
          DocsUI::Section('Why each card is its own reactive root') do
            md <<~MD
              The card carries a rename `<input name="title">`. Field collection
              is **root-wide**, so if the rows were tokenless (the team-inbox
              pattern) every card's title would land in the board's sweep and the
              last one would win. Making each card a **nested reactive root**
              (issue #15) gives every row its own field scope, its own signed
              identity — the Card's GlobalID plus the picked style — and its own
              `move`/`rename`/`archive` actions. The board keeps only what is
              genuinely board-level: the composers and the style picker.
            MD
          end
        end

        def live_counts
          DocsUI::Section('Live counts in every tab') do
            md <<~'MD'
              Row broadcasts alone leave a peer's count badges stale — the
              collection bookkeeping in a reply is the **actor's** HTTP response.
              The board closes that gap with one `reactive:js` chain repainting
              all three badges from server truth, chained onto the actor's reply
              (`reply.js`) AND broadcast to peers after every mutation:

              ```ruby
              def self.count_ops
                Card::LANES.reduce(Phlex::Reactive::JS.new) do |chain, lane|
                  chain.text("#lane-#{lane}-count", Card.by_lane(lane).count)
                end
              end

              def self.broadcast_counts(exclude:)
                broadcast_to(*Card.stream_key, js: count_ops, exclude:)
              end
              ```

              Empty lanes need no bookkeeping at all: the lane list styles its
              own `:empty` pseudo-class, so the placeholder appears the moment
              the last card leaves — on the actor's reply and the peer's
              broadcast alike.
            MD
          end
        end

        def notes
          DocsUI::Section('Notes') do
            md <<~MD
              - The board is **one shared instance** for every visitor — that's
                what makes the second-tab story visible between strangers. Seeds
                restore a starting set on boot.
              - Moves are deliberately **not optimistic**: the exit/enter
                animations are the actor's feedback, and an optimistic hide would
                hide them. `busy: '…'` dedupes a double-click instead. Archive IS
                optimistic — the confirm gate already slowed it down.
              - Cross-tab delivery runs on whatever transport the app has —
                Action Cable here, [pgbus](/docs/transport-pgbus) in production —
                the component code is identical.
              - The composer inputs are named per lane (`title_todo`, …): the
                client's field sweep is root-wide, and three same-named inputs
                would collide.
            MD
          end
        end
      end
    end
  end
end
