# frozen_string_literal: true

require 'rails_helper'

# State-backed loading-states demo: save bumps the signed count and re-renders.
# The disable_with: / busy_on affordances are client-side, so the endpoint
# contract is just the increment + default-deny.
RSpec.describe 'LoadingButton actions', type: :request do
  it 'increments the signed count on save' do
    post_action(LoadingButtonComponent, payload: { 's' => { 'count' => 0 } }, act: 'save')

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('target="loading-button"')
    expect(response.body).to include('data-testid="save"')
  end

  it 'forbids an undeclared action (default-deny)' do
    post_action(LoadingButtonComponent, payload: { 's' => { 'count' => 0 } }, act: 'nuke')
    expect(response).to have_http_status(:forbidden)
  end
end
