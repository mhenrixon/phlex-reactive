# frozen_string_literal: true

Rails.application.routes.draw do
  # Add your docs to an agent over MCP (read-only, stateless — needs `gem "mcp"`).
  # An agent connects with:  claude mcp add --transport http docs <site>/mcp
  post "/mcp" => "docs_kit/mcp#create", as: :mcp
  match "/mcp" => "docs_kit/mcp#method_not_allowed", via: %i[get delete]
  get "/llms-full.txt" => "docs_kit/llms#full", as: :llms_full
  get "/llms.txt" => "docs_kit/llms#index", as: :llms
  get "/docs/search" => "docs_kit/search#index", as: :docs_search
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root 'landings#show'

  # Each reactive demo renders on its own page; the slug resolves to a Demo in
  # the in-memory registry. The phlex-reactive engine mounts POST /reactive/actions
  # itself — do NOT add it here.
  get 'demos/:demo' => 'demos#show', as: :demo

  # Reference docs — hand-authored Phlex pages.
  get 'docs/:doc' => 'docs#show', as: :doc

  # A fixture page exercising docs-kit's multi-language Docs::Example (the sticky
  # language switcher) end-to-end in the browser suite. Test-only — it renders a
  # gem component the real docs don't happen to use (phlex-reactive is Ruby-only;
  # Docs::Example is for multi-language API docs).
  get '_test/code_example' => 'docs_test#code_example' if Rails.env.test?

  # The pgbus dashboard, for visibility into the Postgres-backed transport that
  # powers the live demos in production. Mounted only when pgbus is loaded (it's
  # a production-group gem), so dev/test on SQLite stay unaffected.
  mount Pgbus::Engine => '/pgbus' if defined?(Pgbus::Engine)
end
