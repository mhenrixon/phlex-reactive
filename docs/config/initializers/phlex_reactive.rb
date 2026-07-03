# frozen_string_literal: true

# phlex-reactive config for the docs app. The defaults (renderer =
# ActionController::Base, base_controller = ActionController::Base) already make
# the record-backed demos work; this only wires the failure-surface example.
Rails.application.config.after_initialize do
  # Register the failure-surface demo's authorization error so a DECLARED action
  # that denies returns a clean 403 (client kind=http) — mirroring how a real app
  # registers Pundit::NotAuthorizedError. The page still renders under the
  # render-time undeclared-action guard because `boom` IS declared.
  Phlex::Reactive.authorization_errors << FailureSurfaceComponent::Denied

  # With error_flash set, the endpoint renders a turbo-stream flash the browser
  # SHOWS on a failed action, and the client marks the root data-reactive-error.
  Phlex::Reactive.error_flash = ->(kind) { "Something went wrong (#{kind})." }
end
