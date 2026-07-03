# frozen_string_literal: true

# One Team-inbox row. Keyed off an InboxMessage so its #id is a stable dom_id —
# the append/remove target for the collection helper and the broadcast.
#
# The row carries NO token of its own (no reactive_attrs): its archive/mark-read
# buttons dispatch the CONTAINER's actions (keyed by id) via the generic reactive
# controller it sits inside. The kebab menu is a pure on_client toggle — zero
# round trips. It includes Component only to build those dispatches + the client op.
class InboxMessageComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  def self.model_param_name = :message

  def initialize(message:)
    @message = message
  end

  def id = dom_id(@message)

  def view_template
    li(id:, class: row_classes, data: { testid: 'inbox-row', read: @message.read?.to_s }) do
      unread_dot
      div(class: 'min-w-0 flex-1') do
        div(class: 'truncate text-sm font-medium', data: { testid: 'subject' }) { @message.subject }
        div(class: 'text-xs opacity-60') { "from #{@message.sender}" }
      end
      kebab_menu
    end
  end

  private

  def row_classes
    ['flex items-center gap-3 border-b border-base-200 px-3 py-2',
     ('opacity-60' if @message.read?)].compact
  end

  def unread_dot
    span(class: ['inline-block size-2 rounded-full',
                 (@message.read? ? 'bg-transparent' : 'bg-primary')].compact,
         data: { testid: 'unread-dot' })
  end

  # A pure on_client kebab: clicking toggles this row's menu; a click outside the
  # menu closes it. No token, no POST. The menu holds the reactive archive/mark-read
  # dispatches (the CONTAINER's actions, keyed by this row's id).
  def kebab_menu
    menu_id = "#{id}-menu"
    div(class: 'relative') do
      button(**mix(on_client(:click, js.toggle("##{menu_id}")),
                   class: 'btn btn-ghost btn-xs', data: { testid: 'kebab' })) { '⋯' }
      div(id: menu_id, hidden: true,
          class: 'absolute right-0 z-10 mt-1 flex w-40 flex-col rounded-box border ' \
                 'border-base-300 bg-base-100 p-1 shadow',
          data: { testid: 'kebab-menu' }) do
        mark_read_button unless @message.read?
        archive_button
      end
    end
  end

  def mark_read_button
    button(**mix(on(:mark_read, id: @message.id),
                 class: 'btn btn-ghost btn-xs justify-start', data: { testid: 'mark-read' })) { 'Mark read' }
  end

  # optimistic: { hide: true, to: "##{id}" } hides THIS row the instant you click
  # (the row is tokenless, so to: must target the row's own id, not :root — that
  # would hide the whole inbox). disable_with guards a double-click. reply.remove +
  # broadcast_remove drop it everywhere; a DENIED archive reverts the hide.
  def archive_button
    button(**mix(on(:archive, id: @message.id, disable_with: '…', optimistic: { hide: true, to: "##{id}" }),
                 class: 'btn btn-ghost btn-xs justify-start text-error', data: { testid: 'archive' })) { 'Archive' }
  end
end
