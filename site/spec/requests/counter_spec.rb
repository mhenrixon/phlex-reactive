# frozen_string_literal: true

require 'rails_helper'

# State-backed counter: state rides in the signed token, actions re-render the
# component into its own id.
RSpec.describe 'Counter actions', type: :request do
  it 'increments' do
    post_action(CounterComponent, payload: { 's' => { 'count' => 1 } }, act: 'increment')

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('target="counter"')
    expect(response.body).to match(/>\s*2\s*</) # 1 -> 2
  end

  it 'decrements' do
    post_action(CounterComponent, payload: { 's' => { 'count' => 5 } }, act: 'decrement')
    expect(response.body).to match(/>\s*4\s*</)
  end

  it 'coerces a typed param on set' do
    post_action(CounterComponent, payload: { 's' => { 'count' => 9 } }, act: 'set', params: { count: '0' })
    expect(response.body).to match(/>\s*0\s*</)
  end

  it 'morphs in place on bump_via_morph' do
    post_action(CounterComponent, payload: { 's' => { 'count' => 0 } }, act: 'bump_via_morph')
    expect(response.body).to include('method="morph"')
    expect(response.body).to match(/>\s*1\s*</)
  end

  it 'forbids an undeclared action (default-deny)' do
    post_action(CounterComponent, payload: { 's' => { 'count' => 1 } }, act: 'obliterate')
    expect(response).to have_http_status(:forbidden)
  end
end
