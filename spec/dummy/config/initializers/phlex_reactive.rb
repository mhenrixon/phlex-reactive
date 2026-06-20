# frozen_string_literal: true

# Render reactive components through the dummy's controller so dom_id and other
# view helpers work during re-renders and broadcasts.
Rails.application.config.after_initialize do
  Phlex::Reactive.renderer = DemosController
end
