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
end
