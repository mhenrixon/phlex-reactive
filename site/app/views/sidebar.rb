# frozen_string_literal: true

module Views
  # The drawer sidebar: grouped live demos + reference docs, driven by the Demo
  # and Doc registries. Renders inside the daisyUI drawer-side (the Layout owns
  # responsive visibility), so this is just the panel content — cosmos pattern.
  class Sidebar < Phlex::HTML
    include Phlex::Rails::Helpers::Routes
    include Phlex::Rails::Helpers::Request

    # A lucide icon per nav entry, keyed by slug; groups fall back to a default.
    ICONS = {
      'searchable-combobox' => 'search',
      'counter' => 'calculator',
      'todos' => 'list-checks',
      'chat' => 'messages-square'
    }.freeze
    GROUP_ICON = {
      'Guide' => 'book-open',
      'Examples' => 'code'
    }.freeze

    def view_template
      div(class: 'bg-base-200 flex min-h-full w-72 flex-col') do
        header_section
        div(class: 'flex-1 overflow-y-auto px-2 pb-6') do
          ul(class: 'menu w-full gap-1') do
            nav_group('Demos', Demo.grouped) { |demo| nav_link(demo_path(demo.slug), demo.title, ICONS[demo.slug]) }
            nav_group('Docs', Doc.grouped) { |doc| nav_link(doc_path(doc.slug), doc.title, doc_icon(doc)) }
          end
        end
      end
    end

    private

    def header_section
      div(class: 'flex min-h-16 items-center gap-2 px-4') do
        a(href: root_path, class: 'text-lg font-bold text-base-content') { 'phlex-reactive' }
      end
    end

    # A top-level collapsible group with its sub-groups (e.g. "Demos" → "Inputs").
    def nav_group(heading, grouped, &)
      li do
        details(open: true) do
          summary(class: 'text-xs font-semibold uppercase tracking-wider text-base-content/50') { heading }
          ul do
            grouped.each do |subgroup, items|
              li(class: 'menu-title text-xs') { subgroup }
              items.each { |item| li { yield(item) } }
            end
          end
        end
      end
    end

    def nav_link(href, label, icon_name)
      a(href:, class: link_classes(href)) do
        render Views::Icon.new(icon_name, class: 'size-4 shrink-0') if icon_name
        span(class: 'truncate') { label }
      end
    end

    def link_classes(href)
      active = current_path == href
      ['flex items-center gap-3', (active ? 'menu-active font-medium' : nil)].compact
    end

    def doc_icon(doc)
      GROUP_ICON[doc.group] || 'file-text'
    end

    def current_path
      request&.path
    rescue StandardError
      nil
    end
  end
end
