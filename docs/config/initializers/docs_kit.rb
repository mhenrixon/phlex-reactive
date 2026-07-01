# frozen_string_literal: true

# Per-site configuration for the shared docs chrome (docs-kit). Everything that
# makes this site look like "phlex-reactive" rather than any other docs site
# lives here; the Shell/Sidebar/ThemeSwitcher themselves are shared with the
# daisyUI docs site via the gem.
#
# The themes MUST match the @plugin "daisyui" { themes: ... } block in
# app/assets/stylesheets/application.tailwind.css, or the switcher offers a theme
# the compiled CSS doesn't ship.
Rails.application.config.to_prepare do
  DocsKit.configure do |c|
    c.brand        = 'phlex-reactive'
    c.title_suffix = 'phlex-reactive'
    c.themes       = %w[dark light synthwave retro cyberpunk valentine dracula night coffee nord sunset]
    # Monokai, inlined by Docs::Code — same as the daisyUI docs site, so the two
    # sites' code blocks are identical (no separate rouge stylesheet asset).
    c.code_theme   = 'Rouge::Themes::Monokai'
    c.nav          = -> { DocsNav.groups }
  end
end
