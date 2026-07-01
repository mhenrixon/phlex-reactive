# frozen_string_literal: true

module Views
  module Docs
    module Pages
      class ExampleNotifications < DocsUI::Page
        title 'Notifications / live badges (pure broadcast, no client action)'
        eyebrow 'Examples'

        def lead
          'Not every reactive component needs a client action — sometimes the server just pushes a re-render, ' \
            'using only Streamable broadcasts with no Component mixin.'
        end

        def content
          intro
          badge
          pill
          when_to_use
          transactional_safety
        end

        private

        def intro
          DocsUI::Section('When the server just pushes') do
            DocsUI::Prose() do
              p do
                plain 'Not every reactive component needs a client action. Sometimes the server just needs to '
                strong { 'push' }
                plain ' a re-render — a notification badge that updates when a job finishes, a live metric, a '
                plain '“new items available” pill. This uses only '
                code { 'Phlex::Reactive::Streamable' }
                plain ' (broadcasts), no '
                code { 'Component' }
                plain ' mixin.'
              end
            end
          end
        end

        def badge
          DocsUI::Section('A notification badge') do
            DocsUI::Code(badge_component_source, lexer: :ruby)
            DocsUI::Prose() do
              p { plain 'Subscribe on the page:' }
            end
            DocsUI::Code(subscribe_source, lexer: :ruby)
            DocsUI::Prose() do
              p { plain 'Push an update from anywhere — a model callback, a job, a service:' }
            end
            DocsUI::Code(broadcast_source, lexer: :ruby)
            DocsUI::Prose() do
              p do
                plain 'Now creating a notification re-renders the badge in every tab the user has open. '
                plain 'No client action, no Stimulus, no Action Cable.'
              end
            end
          end
        end

        def pill
          DocsUI::Section('A “new items” pill driven by a background job') do
            DocsUI::Code(job_source, lexer: :ruby)
            DocsUI::Code(status_component_source, lexer: :ruby)
          end
        end

        def when_to_use
          DocsUI::Section('When to use this vs a full reactive component') do
            DocsUI::Prose() do
              ul do
                li do
                  plain 'Server pushes a re-render (job, callback, another user) → '
                  code { 'Streamable' }
                  plain ' + '
                  code { 'broadcast_*_to' }
                  plain '.'
                end
                li do
                  plain 'User clicks/types and the same component updates → add '
                  code { 'Component' }
                  plain ' + '
                  code { 'action' }
                  plain '.'
                end
                li do
                  plain 'Both → add '
                  code { 'Component' }
                  plain '; broadcast from inside the action.'
                end
              end
              p do
                plain 'Because both paths target the component by its '
                code { 'id' }
                plain ', you can start with a pure broadcast badge and later add a '
                code { 'dismiss' }
                plain ' action without changing the target or the subscription.'
              end
            end
            DocsUI::Callout(:note, title: 'For a list, not just a badge') do
              plain 'For an add/remove-row list — rows plus a count badge and an empty-state that toggle as the ' \
                    'list grows and shrinks — see Reactive collections, which declares that whole contract once with '
              code { 'reactive_collection' }
              plain '.'
            end
          end
        end

        def transactional_safety
          DocsUI::Section('Transactional safety') do
            DocsUI::Prose() do
              p do
                plain 'If you broadcast from an '
                code { 'after_create_commit' }
                plain '/'
                code { 'after_update_commit' }
                plain ' callback (or from inside a transaction with pgbus), the broadcast only fires once the '
                plain 'change commits — a rolled-back notification never flashes a phantom badge.'
              end
            end
          end
        end

        def badge_component_source
          <<~RUBY
            class NotificationsBadge < ApplicationComponent
              include Phlex::Reactive::Streamable

              def initialize(user:) = @user = user
              def id = dom_id(@user, :notifications_badge)
              def self.model_param_name = :user

              def view_template
                span(id:, class: "badge") do
                  count = @user.notifications.unread.count
                  plain(count.zero? ? "" : count.to_s)
                end
              end
            end
          RUBY
        end

        def subscribe_source
          <<~RUBY
            # in a layout or header component
            turbo_stream_from current_user, :notifications
          RUBY
        end

        def broadcast_source
          <<~RUBY
            class Notification < ApplicationRecord
              belongs_to :user
              after_create_commit do
                NotificationsBadge.broadcast_replace_to(user, :notifications, model: user)
              end
            end
          RUBY
        end

        def job_source
          <<~RUBY
            class ImportJob < ApplicationJob
              def perform(import)
                import.run!
                # Re-render a status component for everyone watching this import.
                Imports::Status.broadcast_replace_to(import, model: import)
              end
            end
          RUBY
        end

        def status_component_source
          <<~RUBY
            class Imports::Status < ApplicationComponent
              include Phlex::Reactive::Streamable

              def initialize(import:) = @import = import
              def id = dom_id(@import, :status)

              def view_template
                div(id:, class: "import-status \#{@import.status}") do
                  plain @import.status.titleize
                  plain " — \#{@import.processed_count}/\#{@import.total_count}" if @import.running?
                end
              end
            end
          RUBY
        end
      end
    end
  end
end
