# frozen_string_literal: true

# Render reactive components through the dummy's controller so dom_id and other
# view helpers work during re-renders and broadcasts.
Rails.application.config.after_initialize do
  Phlex::Reactive.renderer = DemosController

  # Register the optimistic demo's authorization error so a DECLARED, slow-failing
  # action returns a clean 403 (issue #98 system spec) — mirroring how a real app
  # registers Pundit::NotAuthorizedError. Lets the failing-revert spec observe the
  # applied hint before the (deliberately delayed) failure reverts it, instead of
  # racing a fast default-deny 403.
  Phlex::Reactive.authorization_errors << OptimisticRowComponent::Denied

  # The `boom` fixtures (CounterComponent, FailureSurfaceComponent) deny inside a
  # DECLARED action so their pages still render under the render-time
  # undeclared-action guard (issue #105) while the endpoint still returns 403 —
  # the kind=http failure the lifecycle-events and failure-surface system specs
  # observe. Registering the errors maps them to that 403.
  Phlex::Reactive.authorization_errors << CounterComponent::Denied
  Phlex::Reactive.authorization_errors << FailureSurfaceComponent::Denied
end
