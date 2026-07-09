# frozen_string_literal: true

# One card on the Project board (issue #216) — its OWN reactive root nested
# inside the board (issue #15), because it carries a rename input: a tokenless
# row would feed every card's `title` into the BOARD's root-wide field sweep
# (last one wins). Identity is the Card's GlobalID PLUS the picked effect
# style as signed state (the inline-edit record+state pattern), so a move
# animates with the style THIS visitor chose.
#
# The move is the money shot: ONE reply carries the row's own remove (exit
# animates before the element leaves), the fresh-token append into the new
# lane, and a reactive:js text-op stream repainting all three count badges —
# and the same delta broadcasts to peers with the actor's echo excluded.
class BoardCardComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :card
  reactive_state :style

  # Effects (issue #215): the board's default polish, declared on the ROW so
  # the arriving append template carries the enter attr and the in-DOM row the
  # exit/update attrs. A non-default picked style overrides these PER CALL —
  # the three-level precedence, demoed live.
  reactive_effects enter: :slide, exit: :fade, update: :highlight

  action :move, params: { to: :string }
  action :rename, params: { title: :string }
  action :archive

  def initialize(card:, style: 'default')
    @card = card
    @style = ProjectBoardComponent::STYLES.include?(style) ? style : 'default'
  end

  # Move to an adjacent lane: remove HERE + append THERE + repaint the count
  # badges, all in one reply; peers get the same three streams broadcast.
  def move(to:)
    return reply.morph unless Card::LANES.include?(to) && to != @card.lane

    @card.update!(lane: to, position: Card.next_position(to))
    broadcast_move
    reply.remove(effect: picked_effect)
         .stream(self.class.append(target: ProjectBoardComponent.lane_target(to), model: @card,
                                   style: @style, effect: picked_effect))
         .js(ProjectBoardComponent.count_ops)
  end

  # Enter-to-save inline rename; the morph keeps the input's focus + caret.
  def rename(title:)
    @card.update!(title: title.strip) if title.to_s.strip.present?
    self.class.broadcast_to(*Card.stream_key, replace: @card, morph: true,
                                              exclude: reactive_connection_id)
    reply.morph
  end

  def archive
    @card.destroy!
    self.class.broadcast_to(*Card.stream_key, remove: @card, exclude: reactive_connection_id)
    ProjectBoardComponent.broadcast_counts(exclude: reactive_connection_id)
    reply.remove
         .js(ProjectBoardComponent.count_ops)
         .flash(:notice, 'Card archived', dismiss_after: 2000)
  end

  def view_template
    li(**reactive_root(class: 'flex flex-col gap-1 rounded-field border border-base-300 bg-base-100 p-3 shadow-sm',
                       data: { testid: 'board-card', lane: @card.lane })) do
      title_row
      actions_row
    end
  end

  private

  def title_row
    div(class: 'flex items-center gap-2') do
      input(**mix(on(:rename, event: 'keydown.enter'),
                  name: 'title', value: @card.title, autocomplete: 'off',
                  class: 'input input-ghost input-sm flex-1 font-medium',
                  data: { testid: 'card-title' }))
      # Archive is confirm-gated AND optimistic: the row hides the instant you
      # confirm (to: targets THIS row — :root inside a nested root is the row
      # anyway, but the explicit id keeps the intent obvious).
      button(**mix(on(:archive, confirm: 'Archive this card?',
                                optimistic: { hide: true, to: "##{id}" }),
                   class: 'btn btn-ghost btn-xs text-error', data: { testid: 'archive-card' })) { '×' }
    end
  end

  # Lane moves — deliberately NOT optimistic: the exit/enter animations ARE the
  # actor's feedback (an optimistic hide would hide the exit effect). busy:
  # dedupes a double click instead.
  def actions_row
    idx = Card::LANES.index(@card.lane)
    div(class: 'flex items-center justify-between text-xs') do
      move_button(Card::LANES[idx - 1], '←') if idx.positive?
      span(class: 'flex-1')
      move_button(Card::LANES[idx + 1], '→') if idx < Card::LANES.size - 1
    end
  end

  def move_button(to, glyph)
    button(**mix(on(:move, to:, busy: '…'),
                 class: 'btn btn-ghost btn-xs opacity-70', data: { testid: "move-#{to}" })) do
      "#{glyph} #{to}"
    end
  end

  # 'default' defers to the class-declared effects; anything else overrides
  # per call. 'random' rides through — the client picks a built-in per
  # application.
  def picked_effect
    @style == 'default' ? nil : @style.to_sym
  end

  def broadcast_move
    # Peers see the row leave + arrive with the ROW-DECLARED effects (the
    # picked style is the actor's preference, not the room's).
    self.class.broadcast_to(*Card.stream_key, remove: @card, exclude: reactive_connection_id)
    self.class.broadcast_to(*Card.stream_key, append: @card,
                                              target: ProjectBoardComponent.lane_target(@card.lane),
                                              exclude: reactive_connection_id)
    ProjectBoardComponent.broadcast_counts(exclude: reactive_connection_id)
  end
end
