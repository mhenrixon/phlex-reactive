# frozen_string_literal: true

# The FLAGSHIP example (issue #149): a believable Team inbox that composes the
# whole reactive toolkit in one UI —
#   * reactive_collection rows (archive/mark-read append/remove + count + empty);
#   * an optimistic: archive that hides the row in the same gesture, reverting if
#     the server denies (a "locked" message);
#   * busy: guarding the archive button against a double-click;
#   * cross-tab broadcast_*_to so a teammate's tab stays in sync;
#   * an on_client kebab menu on each row (pure client op, zero round trips);
#   * error_flash + a self-dismissing dismiss_after: toast on the reply.
#
# State-backed container (no single record); the size resolver reads the live DB
# count. Rows are tokenless and dispatch these actions keyed by message id.
class TeamInboxComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component
  include Phlex::Rails::Helpers::TurboStreamFrom

  # A locked message refuses to archive — registered in the initializer so the
  # denial is a clean 403 the client reverts the optimistic hide on.
  class Locked < StandardError; end

  SUBJECTS = ['Deploy finished', 'New signup', 'Payment received', 'Support ticket #4821',
              'Weekly digest'].freeze
  SENDERS = %w[ci billing support system].freeze

  reactive_collection :messages,
                      item: InboxMessageComponent,
                      container: 'inbox-messages',
                      count: 'inbox-count',
                      empty: InboxEmptyComponent,
                      size: -> { InboxMessage.count }

  action :archive, params: { id: :integer }
  action :mark_read, params: { id: :integer }
  action :simulate_incoming

  def id = 'team-inbox'

  # Archive (+ count + empty), broadcast the removal to teammates, and confirm with
  # a self-dismissing flash. A locked message denies → 403 → the client reverts the
  # optimistic hide (the row snaps back) and error_flash surfaces the reason.
  def archive(id:)
    message = InboxMessage.find(id)
    raise Locked, 'This message is locked and cannot be archived.' if message.sender == 'locked'

    message.destroy!
    InboxMessageComponent.broadcast_remove_to(*InboxMessage.stream_key, model: message,
                                                                        exclude: reactive_connection_id)
    reply.remove(:messages, message).flash(:notice, 'Archived', dismiss_after: 2000)
  end

  # Mark read: persist, re-render the row for the actor, and broadcast the updated
  # row to teammates (a replace is id-deduped, so exclude: just spares a redundant echo).
  def mark_read(id:)
    message = InboxMessage.find(id)
    message.update!(read: true)
    InboxMessageComponent.broadcast_replace_to(*InboxMessage.stream_key, model: message,
                                                                         exclude: reactive_connection_id)
    reply.replace
  end

  # Stand in for a teammate/job pushing a new message: create + broadcast_append to
  # every subscribed tab. reply.append updates the actor's own list + count + empty.
  def simulate_incoming
    message = InboxMessage.create!(subject: sample_subject, sender: sample_sender)
    InboxMessageComponent.broadcast_append_to(*InboxMessage.stream_key, target: 'inbox-messages',
                                                                        model: message,
                                                                        exclude: reactive_connection_id)
    reply.append(:messages, message)
  end

  def view_template
    div(**reactive_root(class: 'flex flex-col gap-3')) do
      turbo_stream_from(*InboxMessage.stream_key) # cross-tab sync

      header
      ul(id: 'inbox-messages', class: 'flex flex-col rounded-box border border-base-300') do
        if InboxMessage.exists?
          InboxMessage.active.each { render InboxMessageComponent.new(message: it) }
        else
          render InboxEmptyComponent.new
        end
      end

      div(id: 'flash', class: 'flex flex-col gap-1', data: { testid: 'flash' })
    end
  end

  private

  def header
    div(class: 'flex items-center justify-between') do
      div(class: 'flex items-center gap-2') do
        span(class: 'font-semibold') { 'Team inbox' }
        span(id: 'inbox-count', class: 'badge badge-neutral badge-sm',
             data: { testid: 'inbox-count' }) { InboxMessage.count.to_s }
      end
      button(**mix(on(:simulate_incoming, busy: '…'),
                   class: 'btn btn-sm btn-primary', data: { testid: 'simulate-incoming' })) do
        'Simulate incoming'
      end
    end
  end

  # Deterministic-ish rotation off the DB count (no Random needed at render time).
  def sample_subject = SUBJECTS[InboxMessage.count % SUBJECTS.size]
  def sample_sender  = SENDERS[InboxMessage.count % SENDERS.size]
end
