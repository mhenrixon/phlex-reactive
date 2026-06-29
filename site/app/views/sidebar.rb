# frozen_string_literal: true

module Views
  # The site nav: grouped live demos + reference docs, driven by the Demo and Doc
  # registries so adding an entry there shows up here automatically.
  class Sidebar < Phlex::HTML
    include Phlex::Rails::Helpers::Routes

    def view_template
      aside(class: 'w-64 shrink-0 hidden lg:block') do
        nav(class: 'menu bg-base-200 rounded-box sticky top-4') do
          brand
          section('Demos', Demo.grouped) { |demo| demo_link(demo) }
          section('Docs', Doc.grouped) { |doc| doc_link(doc) }
        end
      end
    end

    private

    def brand
      li(class: 'menu-title') do
        a(href: root_path, class: 'text-lg font-bold text-base-content') { 'phlex-reactive' }
      end
    end

    def section(heading, grouped)
      li do
        details(open: true) do
          summary(class: 'font-semibold') { heading }
          ul do
            grouped.each do |group, items|
              li(class: 'menu-title text-xs') { group }
              items.each { |item| li { yield item } }
            end
          end
        end
      end
    end

    def demo_link(demo)
      a(href: demo_path(demo.slug)) { demo.title }
    end

    def doc_link(doc)
      a(href: doc_path(doc.slug)) { doc.title }
    end
  end
end
