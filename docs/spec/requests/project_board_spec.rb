# frozen_string_literal: true

require 'rails_helper'
require 'turbo/broadcastable/test_helper'

# The Project board flagship (issue #216): a kanban with three fixed lanes.
# Each card is its OWN nested reactive root (record + signed style state); a
# MOVE is the money shot — one reply carries the row's remove (exit animates
# before the element leaves), the append into the new lane, and a reactive:js
# text-op stream repainting all three count badges — while the same delta
# broadcasts to peers with the actor's echo excluded.
RSpec.describe 'Project board actions', type: :request do
  include ActiveSupport::Testing::Assertions
  include Turbo::Broadcastable::TestHelper

  before { Card.delete_all }

  def card_payload(card, style: 'default') = { 'gid' => card.to_gid.to_s, 's' => { 'style' => style } }
  def board_payload(style: 'default') = { 's' => { 'style' => style } }

  describe 'the demo page' do
    it 'renders three lanes with seeded cards and counts' do
      Card.create!(title: 'Ship the board', lane: 'todo')
      Card.create!(title: 'Review PR', lane: 'doing')

      get '/demos/project-board'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('lane-todo-cards')
      expect(response.body).to include('lane-doing-cards')
      expect(response.body).to include('lane-done-cards')
      expect(response.body).to include('Ship the board')
      expect(response.body).to include('lane-todo-count')
    end
  end

  describe 'BoardCardComponent#move' do
    let!(:card) { Card.create!(title: 'Ship it', lane: 'todo') }

    it 'moves the record and replies with remove + append-to-new-lane + the count repaint' do
      post_action(BoardCardComponent, payload: card_payload(card), act: 'move', params: { to: 'doing' })

      expect(response).to have_http_status(:ok)
      expect(card.reload.lane).to eq('doing')
      body = response.body
      expect(body).to include('action="remove"')
      expect(body).to include(%(action="append" target="lane-doing-cards"))
      expect(body).to include('action="reactive:js"')
      expect(body).to include('lane-todo-count')
      expect(body).to include('lane-doing-count')
    end

    it 'stamps the picked style on the row streams (per-call effect override)' do
      post_action(BoardCardComponent, payload: card_payload(card, style: 'scale'),
                                      act: 'move', params: { to: 'doing' })

      expect(response.body).to include('data-reactive-effect="scale"')
    end

    it 'leaves the row streams unstamped on the default style (the row declarations rule)' do
      post_action(BoardCardComponent, payload: card_payload(card), act: 'move', params: { to: 'doing' })

      expect(response.body).not_to include('data-reactive-effect=')
    end

    it 'rejects an unknown lane without moving anything' do
      post_action(BoardCardComponent, payload: card_payload(card), act: 'move', params: { to: 'trash' })

      expect(card.reload.lane).to eq('todo')
    end

    it 'broadcasts the move to peers: row remove + append AND the js count sync' do
      broadcasts = capture_turbo_stream_broadcasts(Card.stream_key) do
        post_action(BoardCardComponent, payload: card_payload(card), act: 'move', params: { to: 'doing' })
      end
      html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin

      expect(html).to include('action="remove"')
      expect(html).to include(%(target="lane-doing-cards"))
      expect(html).to include('action="reactive:js"')
      expect(html).to include('lane-todo-count')
    end
  end

  describe 'BoardCardComponent#rename' do
    let!(:card) { Card.create!(title: 'Old title', lane: 'todo') }

    it 'renames and morphs the row in place (focus survives)' do
      post_action(BoardCardComponent, payload: card_payload(card), act: 'rename',
                                      params: { title: 'New title' })

      expect(card.reload.title).to eq('New title')
      expect(response.body).to include('method="morph"')
    end

    it 'keeps the old title on a blank rename' do
      post_action(BoardCardComponent, payload: card_payload(card), act: 'rename', params: { title: '   ' })

      expect(card.reload.title).to eq('Old title')
    end
  end

  describe 'BoardCardComponent#archive' do
    let!(:card) { Card.create!(title: 'Done with this', lane: 'done') }

    it 'destroys the card, removes the row, repaints counts, and confirms with a flash' do
      expect do
        post_action(BoardCardComponent, payload: card_payload(card), act: 'archive')
      end.to change(Card, :count).by(-1)

      expect(response.body).to include('action="remove"')
      expect(response.body).to include('action="reactive:js"')
      expect(response.body).to include('data-reactive-dismiss-after="2000"')
    end
  end

  describe 'ProjectBoardComponent#add_card' do
    # Composer inputs are named PER LANE (title_todo/…) — the client's field
    # sweep is root-wide, so same-named inputs would collide; the lane param
    # picks the right one.
    it 'creates the card and re-renders the board (composer clears, counts fresh)' do
      expect do
        post_action(ProjectBoardComponent, payload: board_payload, act: 'add_card',
                                           params: { title_todo: 'New card', lane: 'todo' })
      end.to change(Card, :count).by(1)

      expect(response.body).to include('New card')
      expect(response.body).to include('action="replace"')
    end

    it 'rejects a blank title with an error flash, creating nothing' do
      expect do
        post_action(ProjectBoardComponent, payload: board_payload, act: 'add_card',
                                           params: { title_todo: '   ', lane: 'todo' })
      end.not_to change(Card, :count)

      expect(response.body).to include('reactive-flash--error')
    end

    it 'refuses an unknown lane, creating nothing' do
      expect do
        post_action(ProjectBoardComponent, payload: board_payload, act: 'add_card',
                                           params: { title_todo: 'Sneaky', lane: 'trash' })
      end.not_to change(Card, :count)
    end

    it 'broadcasts the new row + count sync to peers' do
      broadcasts = capture_turbo_stream_broadcasts(Card.stream_key) do
        post_action(ProjectBoardComponent, payload: board_payload, act: 'add_card',
                                           params: { title_doing: 'Broadcast me', lane: 'doing' })
      end
      html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin

      expect(html).to include(%(target="lane-doing-cards"))
      expect(html).to include('action="reactive:js"')
    end
  end

  describe 'ProjectBoardComponent#set_style' do
    it 'signs the whitelisted style into state and re-renders with it active' do
      post_action(ProjectBoardComponent, payload: board_payload, act: 'set_style',
                                         params: { style: 'shake' })

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"')
    end

    it 'ignores an unknown style' do
      post_action(ProjectBoardComponent, payload: board_payload, act: 'set_style',
                                         params: { style: 'evil' })

      expect(response).to have_http_status(:ok)
    end
  end
end
