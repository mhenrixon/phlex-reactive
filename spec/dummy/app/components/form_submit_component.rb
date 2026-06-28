# frozen_string_literal: true

# Issue #11: a reactive component whose action fires on a real <form> submit.
# The form carries an explicit `action` to a DISTINCT page so that a native
# (un-prevented) submit causes an observable navigation away from this page —
# exactly the failure the reporter hit (their form action defaulted to "/").
# The reactive controller must preventDefault() synchronously so the submit is
# intercepted and the page never navigates.
class FormSubmitComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :todo
  action :save, params: { title: :string }

  def initialize(todo:)
    @todo = todo
  end

  def id = dom_id(@todo, "formsubmit")

  def save(title:)
    @todo.update!(title:) if title.present?
  end

  def view_template
    div(id:, **reactive_attrs) do
      # Explicit action to a different route: a native submit would land on the
      # nav-probe page. on(:save, event: "submit") must intercept it first.
      form(action: "/nav_probe", method: "post", **mix(on(:save, event: "submit"))) do
        input(name: "title", value: @todo.title, data: { testid: "title" })
        button(type: "submit", data: { testid: "save" }) { "Save" }
      end
      span(data: { testid: "current" }) { @todo.title }
    end
  end
end
