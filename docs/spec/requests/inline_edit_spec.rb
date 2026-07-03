# frozen_string_literal: true

require 'rails_helper'

# Inline edit: record-backed identity (GlobalID) + transient mode as signed state
# (attribute/editing). The endpoint contract — enter edit, save through the schema,
# cancel back to display, default-deny.
RSpec.describe 'InlineEdit actions', type: :request do
  let!(:todo) { Todo.create!(title: 'draft title') }

  def payload = { 'gid' => todo.to_gid.to_s, 's' => { 'attribute' => 'title', 'editing' => false } }

  it 'enters edit mode (renders the field + Save/Cancel)' do
    post_action(InlineEditComponent, payload:, act: 'edit')

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="field"')
    expect(response.body).to include('data-testid="save"')
    expect(response.body).to include('data-testid="cancel"')
  end

  it 'saves the value through the declared schema and returns to display' do
    editing = { 'gid' => todo.to_gid.to_s, 's' => { 'attribute' => 'title', 'editing' => true } }
    post_action(InlineEditComponent, payload: editing, act: 'save', params: { value: 'final title' })

    expect(todo.reload.title).to eq('final title')
    expect(response.body).to include('data-testid="display"')
    expect(response.body).to include('final title')
  end

  it 'cancels back to the display without changing the record' do
    editing = { 'gid' => todo.to_gid.to_s, 's' => { 'attribute' => 'title', 'editing' => true } }
    post_action(InlineEditComponent, payload: editing, act: 'cancel')

    expect(todo.reload.title).to eq('draft title')
    expect(response.body).to include('data-testid="display"')
  end

  it 'forbids an undeclared action' do
    post_action(InlineEditComponent, payload:, act: 'delete_everything')
    expect(response).to have_http_status(:forbidden)
  end
end
