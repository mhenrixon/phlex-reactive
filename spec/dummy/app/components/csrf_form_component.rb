# frozen_string_literal: true

# Issue #42: a reactive component whose view_template renders a real Rails form
# with a CSRF token via `form_authenticity_token`. That helper reads
# `request.env`, so it crashes ("undefined method 'env' for nil") whenever the
# re-render goes through a REQUEST-LESS view context. This component is the
# regression fixture: render_component / a reactive action that re-renders it
# must NOT raise, and the rendered HTML must carry the authenticity token field.
class CsrfFormComponent < ApplicationComponent
  include Phlex::Rails::Helpers::FormAuthenticityToken
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo
  action :save, params: { title: :string }

  def initialize(todo:)
    @todo = todo
  end

  def id = dom_id(@todo, "csrfform")

  def save(title:)
    @todo.update!(title:) if title.present?
  end

  def view_template
    div(id:, **reactive_attrs) do
      form(action: "/todos", method: "post") do
        # The exact helper from the bug report: reads request.env, so it raises
        # through a request-less view context.
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
        input(name: "title", value: @todo.title, data: { testid: "title" })
        button(type: "submit", data: { testid: "save" }) { "Save" }
      end
      span(data: { testid: "current" }) { @todo.title }
    end
  end
end
