# frozen_string_literal: true

# Exercises the optimistic: visual hints (issue #98) end-to-end:
#
#   * an on(:toggle, event: "change", optimistic: { checked: :keep, toggle_class: … })
#     CHECKBOX flips NATIVELY the instant it's clicked — before the (deliberately
#     slow) server morph lands — and the status label's class flips with it;
#   * an on(:boom, optimistic: { add_class: … }) button whose action is
#     UNDECLARED (endpoint default-deny → 403), so the hint is applied then
#     REVERTED when the failure lands;
#   * an on(:destroy, optimistic: { hide: true, to: :root }) button that hides
#     the row INSTANTLY, then reply.remove drops it — the hint is left standing
#     (no re-render of the root) so it never flashes back.
#
# The toggle action sleeps briefly so the system spec can observe the optimistic
# flip DISTINCTLY before the morph reconciles it — a real action is instant, but
# the delay makes "client-first" observable rather than a race.
class OptimisticRowComponent < ApplicationComponent
  include Phlex::Reactive::Component

  reactive_record :todo
  action :toggle
  action :destroy
  # NOTE: :boom is deliberately NOT declared — the endpoint default-denies it
  # (403), the real failure the revert path is proved against.

  def initialize(todo:)
    @todo = todo
  end

  def toggle
    # Deliberate delay so the browser spec sees the optimistic native flip BEFORE
    # the server morph reconciles the checkbox — proving the client painted first.
    sleep 0.4
    @todo.update!(done: !@todo.done?)
  end

  # Hide-then-remove: the optimistic hint hides the row instantly; reply.remove
  # drops it from the DOM. No root re-render, so the hint is left standing and
  # the row never flashes back before removal.
  def destroy
    @todo.destroy!
    reply.remove
  end

  def view_template
    li(**mix(reactive_attrs, id:, data: { testid: "opt-row", done: @todo.done?.to_s })) do
      # The optimistic checkbox: checked:keep lets the native flip happen NOW;
      # toggle_class paints the status label in the same gesture. On success the
      # morph overwrites with server truth; on failure the flip reverts.
      input(**mix(
        on(:toggle, event: "change", optimistic: { checked: :keep, toggle_class: "is-done", to: ".status" }),
        type: "checkbox", checked: @todo.done?, data: { testid: "opt-check" }
      ))
      span(class: ["status", ("is-done" if @todo.done?)], data: { testid: "status" }) { @todo.done? ? "done" : "todo" }

      # Undeclared action → 403 → the add_class hint is applied then reverted.
      button(**mix(on(:boom, optimistic: { add_class: "pending" }), data: { testid: "opt-boom" })) { "boom" }

      # Instant delete: hide the whole row now, remove it on the reply.
      button(**mix(on(:destroy, optimistic: { hide: true, to: :root }), data: { testid: "opt-destroy" })) { "delete" }
    end
  end
end
