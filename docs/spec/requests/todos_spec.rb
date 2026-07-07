# frozen_string_literal: true

require 'rails_helper'

# Record-backed todos: the list adds (broadcasting the new row to other tabs),
# and each row toggles / renames / archives with optimistic hints + a broadcast.
# Row identity is the Todo's GlobalID (reactive_record) — the record is re-found
# server-side, never trusted from the client.
RSpec.describe 'Todo actions', type: :request do
  describe 'TodoListComponent#add' do
    it 'creates a todo from the declared title param and re-renders the list' do
      expect do
        post_action(TodoListComponent, payload: { 's' => { 'build_token' => 'list' } },
                                       act: 'add', params: { title: 'write specs' })
      end.to change(Todo, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('write specs')
      expect(response.body).to include('target="todo-list"')
    end

    it 'ignores a blank title' do
      expect do
        post_action(TodoListComponent, payload: { 's' => { 'build_token' => 'list' } },
                                       act: 'add', params: { title: '   ' })
      end.not_to change(Todo, :count)
    end

    it 'renders the empty-state when there are no rows' do
      post_action(TodoListComponent, payload: { 's' => { 'build_token' => 'list' } },
                                     act: 'add', params: { title: '' })
      expect(response.body).to include('data-testid="todos-empty"')
    end

    it 'guards Add against a double-submit with busy:' do
      # The signed root carries the busy hint so the client disables the button
      # in flight. Assert it renders on the composed page (a fresh add re-render).
      post_action(TodoListComponent, payload: { 's' => { 'build_token' => 'list' } },
                                     act: 'add', params: { title: 'first' })
      expect(response.body).to include('reactive-busy-param')
      expect(response.body).to include('Adding…')
    end
  end

  describe 'TodoItemComponent' do
    let!(:todo) { Todo.create!(title: 'milk', done: false) }

    it 'toggles done via GlobalID identity' do
      post_action(TodoItemComponent, payload: { 'gid' => todo.to_gid.to_s }, act: 'toggle')
      expect(response).to have_http_status(:ok)
      expect(todo.reload.done?).to be(true)
    end

    it 'renders the optimistic checkbox hint so the box flips before the round trip' do
      post_action(TodoItemComponent, payload: { 'gid' => todo.to_gid.to_s }, act: 'toggle')
      # checked: :keep emits the optimistic descriptor on the toggle control.
      expect(response.body).to include('reactive-optimistic-param')
    end

    it 'renames through the declared schema and morphs so the field keeps focus' do
      post_action(TodoItemComponent, payload: { 'gid' => todo.to_gid.to_s },
                                     act: 'rename', params: { title: 'oat milk' })
      expect(todo.reload.title).to eq('oat milk')
      expect(response.body).to include('method="morph"')
    end

    it 'archives — destroys the record and removes the row' do
      gid = todo.to_gid.to_s
      expect do
        post_action(TodoItemComponent, payload: { 'gid' => gid }, act: 'archive')
      end.to change(Todo, :count).by(-1)
      expect(response.body).to include('action="remove"')
    end

    it '404s when the record no longer exists' do
      gid = todo.to_gid.to_s
      todo.destroy!
      post_action(TodoItemComponent, payload: { 'gid' => gid }, act: 'toggle')
      expect(response).to have_http_status(:not_found)
    end

    it 'forbids an undeclared action' do
      post_action(TodoItemComponent, payload: { 'gid' => todo.to_gid.to_s }, act: 'nuke')
      expect(response).to have_http_status(:forbidden)
    end
  end
end
