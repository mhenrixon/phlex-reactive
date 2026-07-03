# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class Broadcasting < DocsUI::Page
        title 'Broadcasting & live updates'
        eyebrow 'Guide'

        def lead
          "Reactive actions update the acting user's screen; broadcasts update everyone " \
            "else's — both target the component by its id, so they compose."
        end

        def content
          pattern
          transports
          stream_keys
          methods_table
          model_mapping
          from_action
          actor_echo
          visible_to
          cross_tab_morph
          transactional
          removing_actor
          js_ops
          reply_js
          presence
        end

        private

        def pattern
          DocsUI::Section('The pattern') do
            md <<~MD
              Reactive **actions** update the acting user's screen. **Broadcasts**
              update everyone else's. Both target the component by its `id`, so they
              compose.

              ```ruby
              # Subscribe (in the view that should receive updates):
              turbo_stream_from @list, :todos

              # Broadcast (from a model callback, job, service, or a reactive action):
              Todos::Item.broadcast_replace_to(@list, :todos, model: @todo)
              ```

              The subscriber and broadcaster must agree on the **same stream key**.
              Pass the same `*streamables` to both `turbo_stream_from` and
              `broadcast_*_to`.
            MD
          end
        end

        def transports
          DocsUI::Section('Two transports: Action Cable or pgbus') do
            md <<~MD
              Every `broadcast_*_to` routes over `Turbo::StreamsChannel`, so it works
              on **either** transport with no code change:

              - **Action Cable** — the Rails default. Broadcasts go over WebSockets.
                Nothing extra to install.
              - **pgbus** — Postgres-backed SSE. Installing it makes the SAME
                `broadcast_*_to` calls route over Postgres instead, and unlocks the
                transactional guarantee, per-connection `exclude:` / `visible_to:`
                scoping, and presence tracking below.

              The plain broadcast API (replace / update / append / prepend / remove /
              js) is identical on both. What pgbus adds are the *guarantees* — the
              transactional deferral, actor-echo suppression, and presence — noted
              inline where they apply.
            MD
          end
        end

        def stream_keys
          DocsUI::Section('Stream keys: pass raw parts, not a built key') do
            md <<~MD
              `broadcast_*_to(*streamables, ...)` builds the stream key itself.
              **Pass raw parts** (a record and/or symbols), not an already-built key
              string:

              ```ruby
              # GOOD — raw parts
              Chat::Message.broadcast_append_to("chat", room, target: "...", model: msg)
              turbo_stream_from "chat", room

              # BAD — double-keying ("chat:lobby" then re-keyed) trips the separator guard
              key = ChatMessage.stream_key(room)             # => "chat:lobby"
              Chat::Message.broadcast_append_to(key, ...)    # ArgumentError under pgbus
              ```

              If you have a helper that returns a built key for the subscriber, pass
              the **same built string** to `turbo_stream_from` only — but give
              `broadcast_*_to` the raw parts. The simplest rule: **use the same raw
              *streamables on both sides.**
            MD
          end
        end

        def methods_table
          DocsUI::Section('The broadcast methods') do
            md <<~MD
              - `.broadcast_replace_to(*streamables, model:, morph:)` — replace the
                element with id `component.id`. Pass `morph: true` for a cross-tab
                morph (see below).
              - `.broadcast_update_to(*streamables, model:)` — replace its *inner*
                HTML.
              - `.broadcast_append_to(*streamables, target:, model:)` — append into
                container `target`.
              - `.broadcast_prepend_to(*streamables, target:, model:)` — prepend into
                `target`.
              - `.broadcast_remove_to(*streamables, model:)` — remove the element with
                id `component.id`.
              - `.broadcast_js_to(*streamables, ops, exclude:, visible_to:, target:)` —
                push **client DOM ops** (class/attr toggles, `dispatch`) to every
                subscriber. Refuses focus ops (see below).

              Every one accepts the transport options `exclude:` and `visible_to:`
              (honored on pgbus, ignored on Action Cable — see those sections).
            MD
          end
        end

        def model_mapping
          DocsUI::Section('How model: maps to the init keyword') do
            md <<~MD
              The `model:` argument is passed to the component's `initialize` under the
              keyword `model_param_name`. For a **record-backed** component
              (`reactive_record`), that keyword is the record name — the SAME keyword
              the action endpoint uses to rebuild the component on a click. So a single
              `initialize(<record>:)` satisfies both clicks and broadcasts:

              ```ruby
              class Todos::Item < ApplicationComponent
                include Phlex::Reactive::Component
                reactive_record :todo
                def initialize(todo:) = @todo = todo   # the keyword must match `reactive_record :todo`
              end

              Todos::Item.broadcast_replace_to(@list, :todos, model: @todo) # builds new(todo: @todo)
              ```

              For a **Streamable-only** component (broadcast-only, no
              `reactive_record`), `model_param_name` defaults to the demodulized,
              underscored class name. When the init keyword differs from that, override
              it:

              ```ruby
              class NotificationsBadge < ApplicationComponent
                include Phlex::Reactive::Streamable
                def initialize(user:) = @user = user
                def self.model_param_name = :user   # class name would be :notifications_badge
              end
              ```
            MD
          end
        end

        def from_action
          DocsUI::Section('Broadcasting from inside a reactive action') do
            md <<~MD
              The acting user gets the action's HTTP response (a replace of the
              component by default, or whatever `reply` the action returns). *Everyone
              else* gets the broadcast. Idiomorph dedupes a `replace` by DOM id, so the
              actor doesn't double-apply — but for `append` / `prepend` (and animations
              or optimistic UI) the echo *would* double-apply. Suppress the actor's own
              echo with `exclude: reactive_connection_id`:

              ```ruby
              def add(title:)
                authorize! @list, :update?
                todo = @list.todos.create!(title:)
                Todos::Item.broadcast_append_to(
                  @list, :todos,
                  target: dom_id(@list, :todos),
                  model: todo,
                  exclude: reactive_connection_id # don't echo to the actor — they got the HTTP response
                )
              end
              ```
            MD
          end
        end

        def actor_echo
          DocsUI::Section('Actor-echo suppression (exclude:)') do
            md <<~MD
              `reactive_connection_id` is the acting client's SSE connection id during
              the action (nil when the client isn't subscribed to a stream, or outside
              an action). The client sends it as `X-Pgbus-Connection`; the action
              endpoint exposes it. Passing it as `exclude:` tells the transport to skip
              delivery to that one connection — so the actor's truth is the HTTP
              response and they never get a duplicate.

              - **With pgbus**: fully honored — the dispatcher skips the excluded
                connection (pgbus ≥ the streams-reactive release).
              - **With Action Cable**: `exclude:` is accepted but ignored (Action Cable
                has no per-connection exclusion); rely on idiomorph dedup for `replace`
                / `update`.

              This is what makes optimistic UI safe: apply the change locally,
              broadcast with `exclude:`, and the actor never gets a conflicting echo of
              their own action.
            MD
          end
        end

        def visible_to
          DocsUI::Section('Scoping a broadcast (visible_to:)') do
            md <<~MD
              Where `exclude:` names ONE connection to skip, `visible_to:` names the
              only connections that should receive the broadcast — an allow-list rather
              than a deny-one. It is a first-class transport option on **every**
              `broadcast_*_to`, alongside `exclude:`:

              ```ruby
              # Only these two connections see the update — everyone else on the stream
              # is skipped. Useful for a private DM row, a per-seat highlight, or a
              # moderator-only control.
              Chat::Message.broadcast_replace_to(
                room, :messages,
                model: msg,
                visible_to: [alice_connection_id, bob_connection_id]
              )
              ```

              Like `exclude:`, `visible_to:` is honored on **pgbus** (per-connection
              delivery) and **ignored on Action Cable** (which has no per-connection
              scoping — every subscriber of the stream receives the broadcast).
            MD
          end
        end

        def cross_tab_morph
          DocsUI::Section('Cross-tab morphing (broadcast_replace_to morph:)') do
            md <<~MD
              A plain `broadcast_replace_to` swaps the whole element. If a peer viewer
              is mid-interaction on that element — a text caret in an input, an open
              `<details>`, scroll position — a swap throws that state away. Pass
              `morph: true` to make the replace **morph in place** instead, so the peer
              tab keeps its focus and caret on the morphed row:

              ```ruby
              # A peer tab editing the same row keeps its caret; only the changed
              # attributes/text are patched in.
              Todos::Item.broadcast_replace_to(@list, :todos, model: @todo, morph: true)
              ```

              This emits `method="morph"` on the broadcast `<turbo-stream>`, so
              idiomorph patches the existing DOM rather than replacing it. Only
              `broadcast_replace_to` takes `morph:` — `update` already patches inner
              HTML, and `append` / `prepend` / `remove` don't replace an existing
              element.
            MD
          end
        end

        def transactional
          DocsUI::Section('Transactional broadcasts (with pgbus)') do
            md <<~MD
              The action endpoint runs your action inside a transaction. With pgbus,
              broadcasts defer to `after_commit`, so:

              - A broadcast inside a transaction that **rolls back never fires** — *and*
                the DB change is undone. No phantom UI update for a change that didn't
                happen.
              - This is the correctness property neither Action Cable nor Livewire give
                you cleanly.

              ```ruby
              ActiveRecord::Base.transaction do
                @order.update!(status: "shipped")
                Orders::Card.broadcast_replace_to(@order.account, model: @order)  # deferred
                ChargeService.capture!(@order)   # if this raises → no broadcast, no status change
              end
              ```
            MD
          end
        end

        def removing_actor
          DocsUI::Section("Removing the actor's own element") do
            md <<~MD
              `destroy`-style actions are the one case where "replace the component by
              its id" doesn't fit — the element should vanish, not be replaced. Return
              `reply.remove` from the action: the actor's element is removed via the
              built-in `Streamable#to_stream_remove` (no endpoint override, no helper to
              add), and other tabs get
              `broadcast_remove_to(..., exclude: reactive_connection_id)`.

              ```ruby
              def destroy
                authorize! @todo, :destroy?
                list = @todo.list
                @todo.destroy!
                # other tabs
                Todos::Item.broadcast_remove_to(list, :todos, model: @todo, exclude: reactive_connection_id)
                reply.remove # this tab
              end
              ```

              For an "undo" affordance, replace with a tombstone state instead of
              removing. See the **reply** API for the full set of reply controls.
            MD
          end
        end

        def js_ops
          DocsUI::Section('Pushing client DOM ops to everyone (broadcast_js_to)') do
            md <<~MD
              Sometimes a broadcast should nudge the UI rather than swap HTML — light up
              a bell, toggle a class, dispatch an app event. `broadcast_js_to` pushes
              the same `js` ops as `reply.js` to every subscriber, over the same
              transport (Action Cable or pgbus):

              ```ruby
              # Light up the bell in every viewer's tab, minus the actor's own connection.
              Notifications::Badge.broadcast_js_to(user, :alerts,
                js.add_class("#bell", "has-unread"), exclude: reactive_connection_id)
              ```
            MD
            DocsUI::Callout(:warning) do
              plain 'Focus ops are refused. '
              code { 'broadcast_js_to' }
              plain ' raises '
              code { 'ArgumentError' }
              plain ' for '
              code { 'focus' }
              plain '/'
              code { 'focus_first' }
              plain " — broadcasting focus would steal it in every subscriber's tab. Focus is an " \
                    'actor-reply concern (use '
              code { 'reply.js' }
              plain ').'
            end
          end
        end

        def reply_js
          DocsUI::Section('Nudging the actor only (reply.js)') do
            md <<~MD
              `broadcast_js_to` is the *everyone* half. Its actor-side sibling is
              `reply.<verb>.js(ops)` — chained onto the reply the action returns, it
              runs client DOM ops on the **acting** user's tab only, and it does so
              AFTER the render streams. Because it rides after the render, a focus op
              sees the freshly rendered (or morphed) DOM:

              ```ruby
              def save(title:)
                @todo.update!(title:)
                # Morph in place, THEN focus the next field + tell a toast host we saved.
                # `focus` is legal here — it's the actor's OWN tab, not a broadcast.
                reply.morph.js(js.focus("[name=next_field]").dispatch("app:saved", detail: { id: @todo.id }))
              end
              ```

              `target:` scopes op resolution on the client; it defaults to the bound
              component's id for `replace` / `morph` / `update` (so `@root` and
              component-relative selectors just work), and to document-scope for a
              subject-free `reply.with`. This is why the focus example above is an
              actor-reply concern and `broadcast_js_to` refuses focus outright:
              `reply.js` targets one tab, a broadcast targets all of them.
            MD
          end
        end

        def presence
          DocsUI::Section("Presence (who's here / typing)") do
            md <<~MD
              pgbus ships presence tracking. Join on render, leave on disconnect,
              broadcast the change:

              ```ruby
              Pgbus.stream(@room).presence.join(
                member_id: current_user.id,
                metadata: { name: current_user.name }
              ) do |member|
                Chat::PresencePill.replace(member: member)  # rendered HTML to broadcast
              end

              Pgbus.stream(@room).presence.members   # current list
              Pgbus.stream(@room).presence.count     # fast count for a "N online" badge
              ```
            MD
            DocsUI::Callout(:tip) do
              plain 'See the pgbus transport guide for the full presence and SSE story.'
            end
          end
        end
      end
    end
  end
end
