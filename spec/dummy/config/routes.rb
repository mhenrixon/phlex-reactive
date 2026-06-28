# frozen_string_literal: true

Rails.application.routes.draw do
  mount Turbo::Engine => "/turbo" if defined?(Turbo::Engine)

  # Example pages exercised by system specs.
  get "counter" => "demos#counter"
  get "chat" => "demos#chat"
  get "todos" => "demos#todos"
  get "notifications" => "demos#notifications"
  get "rich_editor/:id" => "demos#rich_editor"
  get "form_submit/:id" => "demos#form_submit"
  get "nested_editor" => "demos#nested_editor"
  get "nested_params" => "demos#nested_params"
  get "debounce" => "demos#debounce"
  get "morph_grid/:id" => "demos#morph_grid"
  get "partial_grid/:id" => "demos#partial_grid"
  get "document_upload/:id" => "demos#document_upload"
  # Nav probe: where a NON-intercepted form submit would land. Accept POST (and
  # GET) so a native submit produces an observable navigation, not a 404.
  match "nav_probe" => "demos#nav_probe", :via => [:get, :post]

  # The phlex-reactive engine appends POST /reactive/actions itself.
end
