# frozen_string_literal: true

# The site shell. A Phlex layout built on the daisyUI Drawer (same pattern as the
# cosmos admin shell): a fixed topbar, a sidebar that is always visible on desktop
# (lg:drawer-open) and toggles as an overlay on mobile, and the page content in a
# scrollable main. Loads Turbo + the reactive Stimulus controller (auto-pinned by
# the engine) and the daisyUI-compiled Tailwind build.
module Views
  class Layout < Phlex::HTML
    include Phlex::Rails::Helpers::CSRFMetaTags
    include Phlex::Rails::Helpers::CSPMetaTag
    include Phlex::Rails::Helpers::StylesheetLinkTag
    include Phlex::Rails::Helpers::JavaScriptImportmapTags
    include DaisyUI

    DRAWER_ID = 'site-drawer'

    def initialize(title: nil)
      @title = title
    end

    def view_template(&)
      doctype
      html(lang: 'en', data: { theme: 'dark' }) do
        render_head
        body(class: 'bg-base-100 text-base-content') do
          shell(&)
        end
      end
    end

    private

    def render_head
      head do
        title { [@title, 'phlex-reactive'].compact.join(' · ') }
        meta(charset: 'utf-8')
        meta(name: 'viewport', content: 'width=device-width,initial-scale=1')
        csrf_meta_tags
        csp_meta_tag
        # Turbo morphs page-level navigations so a re-render preserves scroll and
        # focus, matching the in-place feel of the reactive components.
        meta(name: 'turbo-refresh-method', content: 'morph')
        meta(name: 'turbo-refresh-scroll', content: 'preserve')
        # `tailwind` is the daisyUI-compiled build; `application` is the Propshaft
        # manifest for any extra app CSS.
        stylesheet_link_tag('tailwind', data: { turbo_track: 'reload' })
        stylesheet_link_tag('application', data: { turbo_track: 'reload' })
        # Rouge syntax-highlight theme for Views::Code (.code-highlight).
        stylesheet_link_tag('rouge', data: { turbo_track: 'reload' })
        javascript_importmap_tags
      end
    end

    # The daisyUI Drawer app-shell. Desktop: sidebar always open (lg:drawer-open).
    # Mobile: sidebar hidden, toggled by the hamburger in the topbar.
    def shell(&)
      Drawer(id: DRAWER_ID, class: 'lg:drawer-open min-h-screen') do |drawer|
        drawer.toggle

        drawer.content(class: 'flex flex-col min-h-screen') do
          topbar
          main(class: 'flex-1 overflow-auto px-4 py-8 md:px-8') do
            div(class: 'mx-auto max-w-4xl', &)
          end
        end

        drawer.side(class: 'z-40') do
          drawer.overlay
          render Views::Sidebar.new
        end
      end
    end

    # Sticky topbar: hamburger (mobile only), brand, theme switcher.
    def topbar
      div(class: 'navbar bg-base-200 border-b border-base-300 sticky top-0 z-30 px-4') do
        div(class: 'flex-1 items-center gap-2') do
          label(for: DRAWER_ID, class: 'btn btn-square btn-ghost btn-sm lg:hidden',
                aria_label: 'Open menu') { render Views::Icon.new('menu', class: 'size-5') }
          a(href: '/', class: 'btn btn-ghost text-lg font-bold') { 'phlex-reactive' }
        end
        div(class: 'flex-none') do
          render Views::ThemeSwitcher.new
        end
      end
    end
  end
end
