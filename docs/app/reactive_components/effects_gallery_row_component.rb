# frozen_string_literal: true

# A row in the effects gallery (issue #215). State-backed: the signed token
# carries its number and the style it arrived with. Its dismiss replies
# reply.remove(effect: <style>) — the per-call form — so the exit animates
# with the SAME style the row entered with, whichever style the gallery was
# set to when it was added.
class EffectsGalleryRowComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  STYLES = %w[fade slide scale highlight shake random].freeze

  reactive_state :n, :style

  action :dismiss

  def initialize(n: 1, style: 'fade')
    @n = n
    @style = STYLES.include?(style) ? style : 'fade'
  end

  def id = "effects-row-#{@n}"

  def dismiss = reply.remove(effect: @style.to_sym)

  def view_template
    row_classes = 'flex items-center justify-between gap-3 rounded-field border border-base-300 bg-base-100 px-3 py-2'
    li(**reactive_root(class: row_classes)) do
      span(class: 'text-sm') { "Row #{@n} — arrived with #{@style}" }
      button(**mix(on(:dismiss), class: 'btn btn-xs btn-ghost', data: { testid: "fx-dismiss-#{@n}" })) { '×' }
    end
  end
end
