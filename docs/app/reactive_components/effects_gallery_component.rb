# frozen_string_literal: true

# The live effects gallery (issue #215). Pick a style, then trigger each hook:
# "Flash" re-renders the gallery with a per-call update effect, "Add row"
# appends a row whose arrival animates (per-call enter), and each row's ×
# animates its exit. Everything here is the PER-CALL form — reply.replace(
# effect:), Row.append(..., effect:), reply.remove(effect:) — with the picked
# style held in signed state; the Effects guide shows the global + per-class
# declarations the rest of the site's demos use.
class EffectsGalleryComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  STYLES = EffectsGalleryRowComponent::STYLES

  reactive_state :style, :next_n

  action :set_style, params: { style: :string }
  action :flash_card
  action :add_row

  def initialize(style: 'fade', next_n: 1)
    @style = STYLES.include?(style) ? style : 'fade'
    @next_n = next_n
  end

  def id = 'effects-gallery'

  # The style param is CLIENT input — whitelist it before it ever reaches an
  # effect: kwarg (an unknown name would raise server-side by design).
  def set_style(style:)
    @style = style if STYLES.include?(style)
    reply.replace
  end

  def flash_card = reply.replace(effect: @style.to_sym)

  def add_row
    stream = EffectsGalleryRowComponent.append(
      target: 'effects-gallery-rows', n: @next_n, style: @style, effect: @style.to_sym
    )
    @next_n += 1
    # No self re-render (a replace would clobber the rows already added) — the
    # token-only refresh keeps repeated adds verifying.
    reply.streams(stream)
  end

  def view_template
    div(**reactive_root(class: 'flex flex-col gap-4', data: { testid: 'effects-gallery' })) do
      style_picker
      div(class: 'flex gap-2') do
        button(**mix(on(:flash_card), class: 'btn btn-sm btn-primary', data: { testid: 'fx-flash' })) do
          "Flash (update: #{@style})"
        end
        button(**mix(on(:add_row), class: 'btn btn-sm', data: { testid: 'fx-add' })) do
          "Add row (enter: #{@style})"
        end
      end
      ul(id: 'effects-gallery-rows', class: 'flex flex-col gap-2')
    end
  end

  private

  def style_picker
    div(class: 'join') do
      STYLES.each do |name|
        button(**mix(on(:set_style, style: name),
                     class: "join-item btn btn-xs #{'btn-active' if name == @style}",
                     data: { testid: "fx-style-#{name}" })) { name }
      end
    end
  end
end
