# frozen_string_literal: true

# Test-only controller: renders a fixture page that exercises docs-kit's
# multi-language Docs::Example (the sticky language switcher) in the browser
# suite. The route is registered only in the test environment (see routes.rb),
# so this is unreachable in development/production.
class DocsTestController < ApplicationController
  def code_example
    render_page(CodeExampleFixture.new)
  end

  # A minimal page with two Docs::Example groups so a system spec can prove the
  # language choice persists globally and syncs across groups.
  class CodeExampleFixture < Phlex::HTML
    def view_template
      DocsUI::Shell(title: 'Code example') do
        h1(id: 'top', class: 'text-2xl font-bold mb-4') { 'Multi-language examples' }
        group('a', 'Anthropic::Client.new', 'anthropic.Anthropic()')
        group('b', 'client.messages.create', 'client.messages.create()')
      end
    end

    private

    def group(name, ruby, python)
      DocsUI::Example() do |ex|
        ex.code(:ruby, filename: "#{name}.rb") { ruby }
        ex.code(:python, filename: "#{name}.py") { python }
      end
    end
  end
end
