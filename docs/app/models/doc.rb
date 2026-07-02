# frozen_string_literal: true

# Registry of the reference docs. Each entry maps a URL slug to its title, sidebar
# group, and the Phlex page class that renders it (hand-authored — the docs are
# self-contained Phlex, so they survive when the gem's docs/ folder is gone at
# deploy). DocsController renders `view_class`.
class Doc
  REGISTRY = [
    { slug: 'installation',          title: 'Installation',            group: 'Guide',    view: 'Installation' },
    { slug: 'architecture',          title: 'Architecture',            group: 'Guide',    view: 'Architecture' },
    { slug: 'security',              title: 'Security & threat model', group: 'Guide',    view: 'Security' },
    { slug: 'broadcasting',          title: 'Broadcasting',            group: 'Guide',    view: 'Broadcasting' },
    { slug: 'transport-pgbus',       title: 'Transport: pgbus',        group: 'Guide',    view: 'TransportPgbus' },
    { slug: 'testing',               title: 'Testing',                 group: 'Guide',    view: 'Testing' },
    { slug: 'performance',           title: 'Performance',             group: 'Guide',    view: 'Performance' },
    { slug: 'examples',              title: 'Examples overview',       group: 'Examples', view: 'ExamplesOverview' },
    { slug: 'example-counter',       title: 'Counter',                 group: 'Examples', view: 'ExampleCounter' },
    { slug: 'example-payment-split', title: 'Payment split',           group: 'Examples',
      view: 'ExamplePaymentSplit' },
    { slug: 'example-todo-list',     title: 'Todo list',               group: 'Examples', view: 'ExampleTodoList' },
    { slug: 'example-inline-edit',   title: 'Inline edit',             group: 'Examples', view: 'ExampleInlineEdit' },
    { slug: 'example-collections',   title: 'Collections',             group: 'Examples', view: 'ExampleCollections' },
    { slug: 'example-notifications', title: 'Notifications',           group: 'Examples',
      view: 'ExampleNotifications' },
    { slug: 'example-chat',          title: 'Cross-tab chat',          group: 'Examples', view: 'ExampleChat' }
  ].freeze

  attr_reader :slug, :title, :group, :view_name

  def initialize(slug:, title:, group:, view:)
    @slug = slug
    @title = title
    @group = group
    @view_name = view
  end

  def self.all
    REGISTRY.map { new(**it) }
  end

  def self.from_slug(slug)
    all.find { it.slug == slug }
  end

  def self.grouped
    all.group_by(&:group)
  end

  # The hand-authored Phlex page class for this doc (nil if not yet written).
  def view_class
    "Views::Docs::Pages::#{view_name}".safe_constantize
  end
end
