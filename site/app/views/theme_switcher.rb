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
          plain 'Theme'
          caret
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

    def caret
      svg(width: '12', height: '12',
          class: 'inline-block h-2 w-2 fill-current opacity-60',
          xmlns: 'http://www.w3.org/2000/svg', viewbox: '0 0 2048 2048') do |s|
        s.path(d: 'M1799 349l242 241-1017 1017L7 590l242-241 775 775 775-775z')
      end
    end
  end
end
