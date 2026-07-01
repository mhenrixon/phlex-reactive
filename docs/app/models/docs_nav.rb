# frozen_string_literal: true

# Builds the docs-kit sidebar nav from this site's registries (Demo + Doc),
# mapping each entry to a DocsKit::NavItem. Kept out of the initializer so the
# nav rebuilds with the registries under code reload and stays testable.
module DocsNav
  # A lucide icon per demo nav entry, keyed by slug.
  DEMO_ICONS = {
    'searchable-combobox' => 'search',
    'counter' => 'calculator',
    'payment-split' => 'scale',
    'todos' => 'list-checks',
    'chat' => 'messages-square'
  }.freeze

  # A lucide icon per doc group.
  DOC_GROUP_ICONS = {
    'Guide' => 'book-open',
    'Examples' => 'code'
  }.freeze

  module_function

  def groups
    nav = {}
    nav['Demos'] = demo_group if demo_group.any?
    nav['Docs'] = doc_group if doc_group.any?
    nav
  end

  def demo_group
    Demo.grouped.transform_values do |items|
      items.map { |demo| DocsKit::NavItem.new(href: "/demos/#{demo.slug}", label: demo.title, icon: DEMO_ICONS[demo.slug]) }
    end
  end

  def doc_group
    Doc.all.select(&:view_class).group_by(&:group).transform_values do |items|
      items.map do |doc|
        DocsKit::NavItem.new(
          href: "/docs/#{doc.slug}",
          label: doc.title,
          icon: DOC_GROUP_ICONS[doc.group] || 'file-text'
        )
      end
    end
  end
end
