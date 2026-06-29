# frozen_string_literal: true

module Views
end

module Components
  extend Phlex::Kit
end

Rails.autoloaders.main.push_dir(
  Rails.root.join("app/views"), namespace: Views
)

Rails.autoloaders.main.push_dir(
  Rails.root.join("app/components"), namespace: Components
)

# Reactive demo components live at the TOP LEVEL (no Components:: prefix), exactly
# as a host app would define them and as the gem's own spec/dummy does. The
# signed identity token carries the class name verbatim, so the demo's class name
# must match what a reader would write — SearchableComboboxComponent, not
# Components::SearchableComboboxComponent.
Rails.autoloaders.main.push_dir(Rails.root.join("app/reactive_components"))

