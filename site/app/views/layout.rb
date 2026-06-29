# frozen_string_literal: true

# The site shell. A Phlex layout that loads Turbo + the reactive Stimulus
# controller (auto-pinned by the engine) and Tailwind/daisyUI, then yields the
# page body. Rendered by ApplicationController via render_page.
module Views
  class Layout < Phlex::HTML
    include Phlex::Rails::Helpers::CSRFMetaTags
    include Phlex::Rails::Helpers::CSPMetaTag
    include Phlex::Rails::Helpers::StylesheetLinkTag
    include Phlex::Rails::Helpers::JavaScriptImportmapTags

    def initialize(title: nil)
      @title = title
    end

    def view_template(&)
      doctype
      html(lang: 'en', data: { theme: 'dark' }) do
        head do
          title { [@title, 'phlex-reactive'].compact.join(' · ') }
          meta(charset: 'utf-8')
          meta(name: 'viewport', content: 'width=device-width,initial-scale=1')
          csrf_meta_tags
          csp_meta_tag
          # Turbo morphs page-level navigations so a re-render preserves scroll
          # and focus, matching the in-place feel of the reactive components.
          meta(name: 'turbo-refresh-method', content: 'morph')
          meta(name: 'turbo-refresh-scroll', content: 'preserve')
          # `tailwind` is the daisyUI-compiled build (app/assets/builds/tailwind.css);
          # `application` is the Propshaft manifest for any extra app CSS.
          stylesheet_link_tag('tailwind', data: { turbo_track: 'reload' })
          stylesheet_link_tag('application', data: { turbo_track: 'reload' })
          javascript_importmap_tags
        end

        body(class: 'min-h-screen bg-base-100 text-base-content') do
          navbar
          div(class: 'mx-auto max-w-7xl px-4 py-8 flex gap-8') do
            render Views::Sidebar.new
            main(class: 'flex-1 min-w-0', &)
          end
        end
      end
    end

    private

    # Top bar with the brand and the daisyUI theme switcher.
    def navbar
      div(class: 'navbar bg-base-200 border-b border-base-300 px-4') do
        div(class: 'flex-1') do
          a(href: '/', class: 'btn btn-ghost text-lg font-bold') { 'phlex-reactive' }
        end
        div(class: 'flex-none') do
          render Views::ThemeSwitcher.new
        end
      end
    end
  end
end
