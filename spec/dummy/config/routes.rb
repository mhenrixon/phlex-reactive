# frozen_string_literal: true

Rails.application.routes.draw do
  mount Turbo::Engine => "/turbo" if defined?(Turbo::Engine)

  # Issue #187: under TRANSPORT=pgbus the dummy mounts pgbus so its SSE stream
  # endpoint (/pgbus/streams) is live and turbo_stream_from routes over it.
  mount Pgbus::Engine => "/pgbus" if ENV["TRANSPORT"] == "pgbus" && defined?(Pgbus::Engine)

  # Example pages exercised by system specs.
  get "counter" => "demos#counter"
  get "debug" => "demos#debug"
  get "failure_surface" => "demos#failure_surface"
  get "network_status" => "demos#network_status"
  get "latency" => "demos#latency"
  get "chat" => "demos#chat"
  get "todos" => "demos#todos"
  get "combobox" => "demos#combobox"
  get "filter_combobox" => "demos#filter_combobox"
  get "new_order" => "demos#new_order"
  get "order/:id" => "demos#order"
  get "post_preview/:id" => "demos#post_preview"
  get "compute_seed" => "demos#compute_seed"
  get "notifications" => "demos#notifications"
  get "reactive_rows" => "demos#reactive_rows"
  get "rich_editor/:id" => "demos#rich_editor"
  get "form_submit/:id" => "demos#form_submit"
  get "dirty_form/:id" => "demos#dirty_form"
  get "nested_editor" => "demos#nested_editor"
  get "nested_params" => "demos#nested_params"
  get "debounce" => "demos#debounce"
  get "dropdown" => "demos#dropdown"
  get "client_tabs" => "demos#client_tabs"
  get "conditional_fieldset" => "demos#conditional_fieldset"
  get "confirm" => "demos#confirm"
  get "client_op_confirm" => "demos#client_op_confirm"
  get "conditional_confirm" => "demos#conditional_confirm"
  get "schedule_confirm" => "demos#schedule_confirm"
  get "optimistic" => "demos#optimistic"
  get "loading_button" => "demos#loading_button"
  get "defer" => "demos#defer"
  get "lazy_stats" => "demos#lazy_stats"
  get "morph_grid/:id" => "demos#morph_grid"
  get "js_focus/:id" => "demos#js_focus"
  get "partial_grid/:id" => "demos#partial_grid"
  get "document_upload/:id" => "demos#document_upload"
  # Nav probe: where a NON-intercepted form submit would land. Accept POST (and
  # GET) so a native submit produces an observable navigation, not a 404.
  match "nav_probe" => "demos#nav_probe", :via => %i[get post]

  # The phlex-reactive engine appends POST /reactive/actions itself.
end
