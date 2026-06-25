# frozen_string_literal: true

Rails.application.routes.draw do
  mount Turbo::Engine => "/turbo" if defined?(Turbo::Engine)

  # Example pages exercised by system specs.
  get "counter" => "demos#counter"
  get "chat" => "demos#chat"
  get "todos" => "demos#todos"
  get "rich_editor/:id" => "demos#rich_editor"

  # The phlex-reactive engine appends POST /reactive/actions itself.
end
