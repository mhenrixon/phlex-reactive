# frozen_string_literal: true

require 'rails_helper'

# Dirty tracking: the class-level `reactive_dirty warn_unsaved: true` declaration
# carries the trackDirty/warn_unsaved descriptors onto the root, and save morphs
# so the field re-renders with a fresh default (badge clears). The dirty
# detection itself is client-side (defaultValue vs value) — the endpoint contract
# is the persist + morph reply + the descriptors on the root.
RSpec.describe 'DirtyForm actions', type: :request do
  let!(:todo) { Todo.create!(title: 'original') }

  it 'renders the track_dirty / warn_unsaved descriptors on the root' do
    post_action(DirtyFormComponent, payload: { 'gid' => todo.to_gid.to_s },
                                    act: 'save', params: { title: 'edited' })

    # The root wires trackDirty on input and arms the unsaved-navigation guard.
    expect(response.body).to include('trackDirty')
    expect(response.body).to include('reactive-warn-unsaved')
  end

  it 'saves the title and morphs so the field default resets (badge clears)' do
    post_action(DirtyFormComponent, payload: { 'gid' => todo.to_gid.to_s },
                                    act: 'save', params: { title: 'edited' })

    expect(todo.reload.title).to eq('edited')
    expect(response.body).to include('method="morph"')
    expect(response.body).to include('edited')
  end

  it 'ignores a blank title (presence guard)' do
    post_action(DirtyFormComponent, payload: { 'gid' => todo.to_gid.to_s },
                                    act: 'save', params: { title: '' })
    expect(todo.reload.title).to eq('original')
  end

  it 'forbids an undeclared action' do
    post_action(DirtyFormComponent, payload: { 'gid' => todo.to_gid.to_s }, act: 'wipe')
    expect(response).to have_http_status(:forbidden)
  end
end
