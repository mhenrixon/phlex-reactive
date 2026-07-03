# frozen_string_literal: true

require 'rails_helper'

# reactive_compute + reactive_text (issue #104): the client mirrors the title and
# recomputes the char counter with no round trip; save reconciles server-side. The
# endpoint contract is the persist + the seeded derived text on re-render.
RSpec.describe 'PostPreview actions', type: :request do
  let!(:todo) { Todo.create!(title: 'hello') }

  it 'saves the title and seeds the derived preview + counter on re-render' do
    post_action(PostPreviewComponent, payload: { 'gid' => todo.to_gid.to_s },
                                      act: 'save', params: { title: 'a longer title' })

    expect(todo.reload.title).to eq('a longer title')
    # The identity mirror + the reducer output are both seeded server-side.
    expect(response.body).to include('data-reactive-text="title"')
    expect(response.body).to include('data-reactive-text="char_count"')
    # The seeded counter matches the Ruby twin ("<len>/80").
    expect(response.body).to include('14/80')
    # The server-only echo confirms the persisted value.
    expect(response.body).to include('a longer title')
  end

  it 'carries the compute binding on the root so the client reducer can find it' do
    post_action(PostPreviewComponent, payload: { 'gid' => todo.to_gid.to_s },
                                      act: 'save', params: { title: 'x' })
    expect(response.body).to include('data-reactive-compute')
  end

  it 'forbids an undeclared action' do
    post_action(PostPreviewComponent, payload: { 'gid' => todo.to_gid.to_s }, act: 'nuke')
    expect(response).to have_http_status(:forbidden)
  end
end
