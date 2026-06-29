# frozen_string_literal: true

module Views
  # daisyUI theme switcher — a dropdown of radio inputs with the `theme-controller`
  # class. daisyUI swaps the page theme (data-theme on :root) with ZERO JavaScript
  # via a CSS :has() selector, so this fits the gem's "no custom JS" ethos.
  class ThemeSwitcher < Phlex::HTML
    # Must match the themes enabled in app/assets/tailwind/application.css.
    THEMES = %w[dark light synthwave retro cyberpunk valentine dracula night coffee nord sunset].freeze

    def view_template
      div(class: 'dropdown dropdown-end') do
        div(tabindex: '0', role: 'button', class: 'btn btn-sm btn-ghost gap-1') do
          render Views::Icon.new('palette', class: 'size-4')
          plain 'Theme'
        end
        ul(tabindex: '0',
           class: 'dropdown-content bg-base-300 rounded-box z-10 w-44 p-2 shadow-2xl max-h-96 overflow-y-auto') do
          THEMES.each { theme_option(it) }
        end
      end
    end

    private

    def theme_option(theme)
      li do
        input(
          type: 'radio',
          name: 'theme-dropdown',
          value: theme,
          class: 'theme-controller btn btn-sm btn-block btn-ghost justify-start',
          aria_label: theme.capitalize,
          data: { testid: "theme-#{theme}" }
        )
      end
    end
  end
end
