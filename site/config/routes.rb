Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "landings#show"

  # Each reactive demo renders on its own page; the slug resolves to a Demo in
  # the in-memory registry. The phlex-reactive engine mounts POST /reactive/actions
  # itself — do NOT add it here.
  get "demos/:demo" => "demos#show", as: :demo

  # Reference docs, rendered from Markdown as first-class Phlex pages.
  get "docs/:doc" => "docs#show", as: :doc
end
