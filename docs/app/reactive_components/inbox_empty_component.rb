# frozen_string_literal: true

# The empty-state for the Team inbox reactive_collection. Removed by its stable
# #id when the first message arrives, appended back when the last is archived.
class InboxEmptyComponent < Phlex::HTML
  include Phlex::Reactive::Streamable

  def id = 'inbox-empty'

  def view_template
    li(id:, class: 'py-8 text-center text-sm opacity-60', data: { testid: 'inbox-empty' }) do
      'Inbox zero 🎉 — nothing left to triage.'
    end
  end
end
