# frozen_string_literal: true

# A reactive "context switcher" for the docs — the docs dogfood the gem they
# document. It is state-backed: the chosen `key` rides in the signed token, and
# clicking a tab fires a reactive action that re-renders this component in place
# to show the matching content (no custom JavaScript, no page reload).
#
# The options + their content are supplied by the host doc page via a registry
# id, so the same component drives any "pick one of N contexts" widget (e.g.
# transport: Action Cable vs pgbus). Content is looked up server-side from the
# frozen registry — never shipped to or trusted from the client.
class ContextSwitcherComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :registry, :key

  action :switch, params: { key: :string }

  def initialize(registry:, key: nil)
    @registry = registry.to_s
    @key = key.presence || options.first&.fetch(:key)
  end

  def id = "context-switcher-#{@registry}"

  # Re-render with the chosen context. The key MUST be a real option (no trusting
  # client input); an unknown key is ignored.
  def switch(key:)
    @key = key if options.any? { it[:key] == key }
    reply.morph
  end

  def view_template
    div(**reactive_root(class: 'not-prose my-6')) do
      tabs
      panel
    end
  end

  private

  # The options for this widget, from the doc registry (frozen, server-side).
  def options
    DocContexts.options(@registry)
  end

  def current
    options.find { it[:key] == @key } || options.first
  end

  def tabs
    div(role: 'tablist', class: 'tabs tabs-box w-fit') do
      options.each do |opt|
        active = opt[:key] == @key
        button(**mix(
          on(:switch, key: opt[:key]),
          role: 'tab',
          class: ['tab', ('tab-active' if active)],
          data: { testid: "context-tab-#{opt[:key]}" }
        )) { opt[:label] }
      end
    end
  end

  def panel
    opt = current
    div(class: 'mt-3', data: { testid: 'context-panel' }) do
      p(class: 'mb-2 text-sm text-base-content/70') { opt[:summary] } if opt[:summary]
      render Views::Code.new(opt[:code], lexer: opt.fetch(:lexer, :ruby), filename: opt[:filename])
    end
  end
end
