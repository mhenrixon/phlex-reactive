# frozen_string_literal: true

# A plain-Ruby registry of the live reactive demos (no DB). Drives both the
# sidebar nav and DemosController#show. Each entry maps a URL slug to the demo's
# title, group, and the reactive component class that renders live on the page.
#
# PR #1 ships only the searchable combobox; Counter/Todos/Chat join in PR #2.
class Demo
  REGISTRY = [
    {
      slug: 'searchable-combobox',
      title: 'Searchable combobox',
      group: 'Inputs',
      blurb: 'Debounced live filtering over an in-memory list — zero custom JavaScript.',
      component: 'SearchableComboboxComponent',
      call_site: <<~RUBY
        # Mount the component anywhere a Phlex view renders:
        render SearchableComboboxComponent.new

        # Pre-seed the search or selection (both ride in the signed token):
        render SearchableComboboxComponent.new(query: "ru", selected_name: "Ruby")
      RUBY
    }
  ].freeze

  attr_reader :slug, :title, :group, :blurb, :component_name, :call_site

  def initialize(slug:, title:, group:, blurb:, component:, call_site:)
    @slug = slug
    @title = title
    @group = group
    @blurb = blurb
    @component_name = component
    @call_site = call_site
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

  def component_class
    component_name.constantize
  end
end
