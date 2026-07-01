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
          stream_keys
          methods_table
          model_mapping
          from_action
          actor_echo
          transactional
          removing_actor
          presence
        end

        private

        def pattern
          DocsUI::Section('The pattern') do
            DocsUI::Prose() do
              p do
                plain 'Reactive '
                strong { 'actions' }
                plain " update the acting user's screen. "
                strong { 'Broadcasts' }
                plain ' update everyone else\'s. Both target the component by its '
                code { 'id' }
                plain ', so they compose.'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              # Subscribe (in the view that should receive updates):
              turbo_stream_from @list, :todos

              # Broadcast (from a model callback, job, service, or a reactive action):
              Todos::Item.broadcast_replace_to(@list, :todos, model: @todo)
            RUBY
            DocsUI::Prose() do
              p do
                plain 'The subscriber and broadcaster must agree on the '
                strong { 'same stream key' }
                plain '. Pass the same '
                code { '*streamables' }
                plain ' to both '
                code { 'turbo_stream_from' }
                plain ' and '
                code { 'broadcast_*_to' }
                plain '.'
              end
            end
          end
        end

        def stream_keys
          DocsUI::Section('Stream keys: pass raw parts, not a built key') do
            DocsUI::Prose() do
              p do
                code { 'broadcast_*_to(*streamables, ...)' }
                plain ' builds the stream key itself. '
                strong { 'Pass raw parts' }
                plain ' (a record and/or symbols), not an already-built key string:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              # GOOD — raw parts
              Chat::Message.broadcast_append_to("chat", room, target: "...", model: msg)
              turbo_stream_from "chat", room

              # BAD — double-keying ("chat:lobby" then re-keyed) trips the separator guard
              key = ChatMessage.stream_key(room)             # => "chat:lobby"
              Chat::Message.broadcast_append_to(key, ...)    # ArgumentError under pgbus
            RUBY
            DocsUI::Prose() do
              p do
                plain 'If you have a helper that returns a built key for the subscriber, pass the '
                strong { 'same built string' }
                plain ' to '
                code { 'turbo_stream_from' }
                plain ' only — but give '
                code { 'broadcast_*_to' }
                plain ' the raw parts. The simplest rule: '
                strong { 'use the same raw *streamables on both sides.' }
              end
            end
          end
        end

        def methods_table
          DocsUI::Section('The broadcast methods') do
            DocsUI::Prose() do
              ul do
                li do
                  code { '.broadcast_replace_to(*streamables, model:)' }
                  plain ' — replace the element with id '
                  code { 'component.id' }
                  plain '.'
                end
                li do
                  code { '.broadcast_update_to(*streamables, model:)' }
                  plain ' — replace its '
                  em { 'inner' }
                  plain ' HTML.'
                end
                li do
                  code { '.broadcast_append_to(*streamables, target:, model:)' }
                  plain ' — append into container '
                  code { 'target' }
                  plain '.'
                end
                li do
                  code { '.broadcast_prepend_to(*streamables, target:, model:)' }
                  plain ' — prepend into '
                  code { 'target' }
                  plain '.'
                end
                li do
                  code { '.broadcast_remove_to(*streamables, model:)' }
                  plain ' — remove the element with id '
                  code { 'component.id' }
                  plain '.'
                end
              end
            end
          end
        end

        def model_mapping
          DocsUI::Section('How model: maps to the init keyword') do
            DocsUI::Prose() do
              p do
                plain 'The positional '
                code { 'model:' }
                plain " is passed to the component's "
                code { 'initialize' }
                plain ' under the keyword '
                code { 'model_param_name' }
                plain '. For a '
                strong { 'record-backed' }
                plain ' component ('
                code { 'reactive_record' }
                plain '), that keyword is the record name — the SAME keyword the action endpoint ' \
                      'uses to rebuild the component on a click. So a single '
                code { 'initialize(<record>:)' }
                plain ' satisfies both clicks and broadcasts:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              class Todos::Item < ApplicationComponent
                include Phlex::Reactive::Streamable
                include Phlex::Reactive::Component
                reactive_record :todo
                def initialize(todo:) = @todo = todo   # the keyword must match `reactive_record :todo`
              end

              Todos::Item.broadcast_replace_to(@list, :todos, model: @todo) # builds new(todo: @todo)
            RUBY
            DocsUI::Prose() do
              p do
                plain 'For a '
                strong { 'Streamable-only' }
                plain ' component (broadcast-only, no '
                code { 'reactive_record' }
                plain '), '
                code { 'model_param_name' }
                plain ' defaults to the demodulized, underscored class name. When the init keyword ' \
                      'differs from that, override it:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              class NotificationsBadge < ApplicationComponent
                include Phlex::Reactive::Streamable
                def initialize(user:) = @user = user
                def self.model_param_name = :user   # class name would be :notifications_badge
              end
            RUBY
          end
        end

        def from_action
          DocsUI::Section('Broadcasting from inside a reactive action') do
            DocsUI::Prose() do
              p do
                plain 'The acting user gets the action\'s HTTP response (a replace of the component by ' \
                      'default, or whatever '
                code { 'reply' }
                plain ' the action returns). '
                em { 'Everyone else' }
                plain ' gets the broadcast. Idiomorph dedupes a '
                code { 'replace' }
                plain ' by DOM id, so the actor doesn\'t double-apply — but for '
                code { 'append' }
                plain '/'
                code { 'prepend' }
                plain ' (and animations or optimistic UI) the echo '
                em { 'would' }
                plain ' double-apply. Suppress the actor\'s own echo with '
                code { 'exclude: reactive_connection_id' }
                plain ':'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
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
            RUBY
          end
        end

        def actor_echo
          DocsUI::Section('Actor-echo suppression (exclude:)') do
            DocsUI::Prose() do
              p do
                code { 'reactive_connection_id' }
                plain " is the acting client's SSE connection id during the action (nil when the client " \
                      'isn\'t subscribed to a stream, or outside an action). The client sends it as '
                code { 'X-Pgbus-Connection' }
                plain '; the action endpoint exposes it. Passing it as '
                code { 'exclude:' }
                plain ' tells the transport to skip delivery to that one connection — so the actor\'s ' \
                      'truth is the HTTP response and they never get a duplicate.'
              end
              ul do
                li do
                  strong { 'With pgbus' }
                  plain ': fully honored — the dispatcher skips the excluded connection ' \
                        '(pgbus ≥ the streams-reactive release).'
                end
                li do
                  strong { 'With Action Cable' }
                  plain ': '
                  code { 'exclude:' }
                  plain ' is accepted but ignored (Action Cable has no per-connection exclusion); ' \
                        'rely on idiomorph dedup for '
                  code { 'replace' }
                  plain '/'
                  code { 'update' }
                  plain '.'
                end
              end
              p do
                plain 'This is what makes optimistic UI safe: apply the change locally, broadcast with '
                code { 'exclude:' }
                plain ', and the actor never gets a conflicting echo of their own action.'
              end
            end
          end
        end

        def transactional
          DocsUI::Section('Transactional broadcasts (with pgbus)') do
            DocsUI::Prose() do
              p do
                plain 'The action endpoint runs your action inside a transaction. With pgbus, broadcasts ' \
                      'defer to '
                code { 'after_commit' }
                plain ', so:'
              end
              ul do
                li do
                  plain 'A broadcast inside a transaction that '
                  strong { 'rolls back never fires' }
                  plain ' — '
                  em { 'and' }
                  plain ' the DB change is undone. No phantom UI update for a change that didn\'t happen.'
                end
                li do
                  plain 'This is the correctness property neither Action Cable nor Livewire give you cleanly.'
                end
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              ActiveRecord::Base.transaction do
                @order.update!(status: "shipped")
                Orders::Card.broadcast_replace_to(@order.account, model: @order)  # deferred
                ChargeService.capture!(@order)   # if this raises → no broadcast, no status change
              end
            RUBY
          end
        end

        def removing_actor
          DocsUI::Section("Removing the actor's own element") do
            DocsUI::Prose() do
              p do
                code { 'destroy' }
                plain '-style actions are the one case where "replace the component by its id" doesn\'t ' \
                      'fit — the element should vanish, not be replaced. Return '
                code { 'reply.remove' }
                plain ' from the action: the actor\'s element is removed via the built-in '
                code { 'Streamable#to_stream_remove' }
                plain ' (no endpoint override, no helper to add), and other tabs get '
                code { 'broadcast_remove_to(..., exclude: reactive_connection_id)' }
                plain '.'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              def destroy
                authorize! @todo, :destroy?
                list = @todo.list
                @todo.destroy!
                # other tabs
                Todos::Item.broadcast_remove_to(list, :todos, model: @todo, exclude: reactive_connection_id)
                reply.remove # this tab
              end
            RUBY
            DocsUI::Prose() do
              p do
                plain 'For an "undo" affordance, replace with a tombstone state instead of removing. See the '
                strong { 'reply' }
                plain ' API for the full set of reply controls.'
              end
            end
          end
        end

        def presence
          DocsUI::Section('Presence (who\'s here / typing)') do
            DocsUI::Prose() do
              p do
                plain 'pgbus ships presence tracking. Join on render, leave on disconnect, broadcast the change:'
              end
            end
            DocsUI::Code(<<~RUBY, lexer: :ruby)
              Pgbus.stream(@room).presence.join(
                member_id: current_user.id,
                metadata: { name: current_user.name }
              ) do |member|
                Chat::PresencePill.replace(member: member)  # rendered HTML to broadcast
              end

              Pgbus.stream(@room).presence.members   # current list
              Pgbus.stream(@room).presence.count     # fast count for a "N online" badge
            RUBY
            DocsUI::Callout(:tip) do
              plain 'See the pgbus transport guide for the full presence and SSE story.'
            end
          end
        end
      end
    end
  end
end
