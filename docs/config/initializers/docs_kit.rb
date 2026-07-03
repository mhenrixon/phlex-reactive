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
    # The one-line summary agents read first in /llms.txt (the llmstxt.org
    # blockquote under the H1).
    c.tagline = 'Server-driven reactive Phlex components over a Postgres-backed ' \
                'live transport — no bespoke JS, no client framework.'
    c.themes = %w[dark light synthwave retro cyberpunk valentine dracula night coffee nord sunset]

    # Code blocks: a light base with a dark override, so the highlight stays
    # readable when the switcher lands on a dark daisyUI theme. CSS-only scoping
    # ([data-theme=X]) — no JS, no flash.
    c.code_theme      = 'Rouge::Themes::Github'
    c.code_theme_dark = 'Rouge::Themes::Monokai'

    # The sidebar nav interleaves Demos + Docs, so it stays a bespoke lambda.
    c.nav = -> { DocsNav.groups }

    # nav_registries feeds the AI surfaces (/llms.txt, /llms-full.txt, search)
    # from the registry — the custom c.nav above only drives the sidebar, so
    # without this the AI index would be empty. Doc (the reference-page registry)
    # supplies #nav_items; the live Demos aren't authored .md pages, so they're
    # not indexed.
    c.nav_registries = { 'Docs' => Doc }
  end
end
