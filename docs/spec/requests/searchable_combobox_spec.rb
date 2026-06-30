# frozen_string_literal: true

require 'rails_helper'

# The searchable combobox is the docs site's headline reactive demo (issue #51).
# State-backed: `query` + `selected_name` ride in the signed token; `search`
# filters a frozen in-memory list; `select` reports a choice back. These specs
# lock the endpoint contract — default-deny, schema coercion, the morph reply,
# and server-side membership validation on select.
RSpec.describe 'SearchableCombobox actions', type: :request do
  describe 'search' do
    it 'filters the in-memory list and returns a morphing self-replace' do
      post_action(SearchableComboboxComponent,
                  payload: { 's' => { 'query' => '', 'selected_name' => nil } },
                  act: 'search', params: { query: 'ru' })

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('action="replace"')
      expect(response.body).to include('method="morph"')
      expect(response.body).to include('target="language-combobox"')
      # "ru" matches Ruby and Rust; not Elixir.
      expect(response.body).to include('Ruby')
      expect(response.body).to include('Rust')
      expect(response.body).not_to include('Elixir')
      # The input echoes exactly what was typed (the morph focus guarantee).
      expect(response.body).to include('value="ru"')
    end

    it 'coerces the query param through the declared schema' do
      post_action(SearchableComboboxComponent,
                  payload: { 's' => { 'query' => 'old', 'selected_name' => nil } },
                  act: 'search', params: { query: 'eli' })

      expect(response.body).to include('Elixir')
      expect(response.body).to include('value="eli"')
    end
  end

  describe 'select' do
    it 'sets the selection when the name is a real list member' do
      post_action(SearchableComboboxComponent,
                  payload: { 's' => { 'query' => 'ru', 'selected_name' => nil } },
                  act: 'select', params: { name: 'Ruby' })

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="combobox-selection"')
      expect(response.body).to include('Ruby')
    end

    it 'ignores a name that is NOT in the list (no client-trusted state)' do
      post_action(SearchableComboboxComponent,
                  payload: { 's' => { 'query' => '', 'selected_name' => nil } },
                  act: 'select', params: { name: "Malbolge'); DROP TABLE languages;--" })

      expect(response).to have_http_status(:ok)
      # The bogus name never becomes the selection.
      expect(response.body).not_to include('DROP TABLE')
      expect(response.body).not_to include('data-testid="combobox-selection"')
    end
  end

  describe 'default-deny' do
    it 'forbids an undeclared action' do
      post_action(SearchableComboboxComponent,
                  payload: { 's' => { 'query' => '', 'selected_name' => nil } },
                  act: 'truncate_everything', params: { query: 'x' })

      expect(response).to have_http_status(:forbidden)
    end
  end
end
