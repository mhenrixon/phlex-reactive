# frozen_string_literal: true

# A single notification row in the reactive_collection demo (issue #35). Keyed
# off a Todo record so its #id is a stable dom_id — the append/remove target for
# the collection helper.
#
# The row carries NO token of its own (no reactive_attrs): its dismiss button
# dispatches the CONTAINER's `dismiss` action via the generic reactive controller
# it sits inside, so the client sends the container's token. It includes
# Component only to use `on` to build that dispatch — the same attrs whether the
# row is rendered on first paint or streamed in by reply.append.
class NotificationRowComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  def self.model_param_name = :todo

  def initialize(todo:)
    @todo = todo
  end

  def id = dom_id(@todo)

  def view_template
    li(id:, class: "notification", data: { testid: "notification" }) do
      span(class: "body") { @todo.title }
      button(**mix(on(:dismiss, id: @todo.id), data: { testid: "dismiss" })) { "×" }
    end
  end
end
