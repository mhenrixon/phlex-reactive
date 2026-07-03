# frozen_string_literal: true

require 'rails_helper'

# The failure surface (issue #100): a declared action that denies returns a clean
# 403 (error registered in the initializer), the endpoint renders an error_flash,
# and a normal action succeeds. flash_now emits a self-dismissing toast.
RSpec.describe 'FailureSurface actions', type: :request do
  it 'returns 403 and an error flash when the action denies' do
    post_action(FailureSurfaceComponent, payload: { 's' => { 'count' => 0 } }, act: 'boom')

    expect(response).to have_http_status(:forbidden)
    # error_flash renders the configured message into the flash target.
    expect(response.body).to include('Something went wrong')
  end

  it 'succeeds on a normal action and re-renders' do
    post_action(FailureSurfaceComponent, payload: { 's' => { 'count' => 2 } }, act: 'succeed')

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('target="failure-surface"')
    expect(response.body).to match(/>\s*3\s*</)
  end

  it 'emits a self-dismissing flash on flash_now' do
    post_action(FailureSurfaceComponent, payload: { 's' => { 'count' => 0 } }, act: 'flash_now')

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('self-dismisses')
    expect(response.body).to include('data-reactive-dismiss-after="2500"')
  end

  it 'forbids an undeclared action (default-deny)' do
    post_action(FailureSurfaceComponent, payload: { 's' => { 'count' => 0 } }, act: 'nuke')
    expect(response).to have_http_status(:forbidden)
  end
end
