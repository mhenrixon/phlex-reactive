# frozen_string_literal: true

# Lucide icon rendering, adapted from the cosmos IconHelper. `_lucide(name, **)`
# returns the inline SVG string for a synced lucide icon; a missing name falls
# back to a question-mark icon (in production) instead of raising.
#
# In Phlex views, render it with `raw(safe(_lucide("search", class: "size-4")))`,
# or use the Docs::Icon component (from docs-kit) which wraps rails_icons directly.
module IconHelper
  MISSING_ICON = 'circle-question-mark'

  def _lucide(name, **)
    icon(name, library: 'lucide', **)
  end

  private

  def icon(name, library: RailsIcons.configuration.default_library, variant: nil, **arguments)
    Icons::Icon.new(name: name.to_s.dasherize, library:, variant:, arguments:).svg
  rescue Icons::IconNotFound
    raise if Rails.env.local?

    Icons::Icon.new(name: MISSING_ICON, library:, variant:, arguments:).svg
  end
end
