# frozen_string_literal: true

# Registry of the reference docs (ported from the gem's docs/*.md). Each entry
# maps a URL slug to its title, sidebar group, and the source Markdown file under
# site/docs_content. Docs::Show renders the file as a first-class Phlex page.
class Doc
  ROOT = Rails.root.join('docs_content')

  REGISTRY = [
    { slug: 'installation',     title: 'Installation',            group: 'Guide', file: 'installation.md' },
    { slug: 'architecture',     title: 'Architecture',            group: 'Guide', file: 'architecture.md' },
    { slug: 'security',         title: 'Security & threat model', group: 'Guide', file: 'security.md' },
    { slug: 'broadcasting',     title: 'Broadcasting',            group: 'Guide', file: 'broadcasting.md' },
    { slug: 'transport-pgbus',  title: 'Transport: pgbus',        group: 'Guide', file: 'transport-pgbus.md' },
    { slug: 'testing',          title: 'Testing',                 group: 'Guide', file: 'testing.md' },
    { slug: 'performance',      title: 'Performance',             group: 'Guide', file: 'performance.md' },
    { slug: 'examples',         title: 'Examples overview',       group: 'Examples', file: 'examples/index.md' },
    { slug: 'example-counter',  title: 'Counter',                 group: 'Examples', file: 'examples/counter.md' },
    { slug: 'example-todo-list', title: 'Todo list',              group: 'Examples', file: 'examples/todo_list.md' },
    { slug: 'example-inline-edit', title: 'Inline edit',          group: 'Examples', file: 'examples/inline_edit.md' },
    { slug: 'example-collections', title: 'Collections',          group: 'Examples', file: 'examples/collections.md' },
    { slug: 'example-notifications', title: 'Notifications', group: 'Examples',
      file: 'examples/notifications.md' },
    { slug: 'example-chat', title: 'Cross-tab chat', group: 'Examples', file: 'examples/chat.md' }
  ].freeze

  attr_reader :slug, :title, :group, :file

  def initialize(slug:, title:, group:, file:)
    @slug = slug
    @title = title
    @group = group
    @file = file
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

  def path
    ROOT.join(file)
  end

  def body
    path.read
  end
end
