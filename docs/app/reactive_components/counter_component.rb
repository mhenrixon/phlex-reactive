# frozen_string_literal: true

# State-backed reactive counter (no DB). The signed token carries `count`; each
# action re-renders the component into its own #id. Demonstrates the simplest
# reactive shape: reactive_state + actions with and without params, plus a few
# reply.* reply styles (a flash, an in-place morph, a redirect).
class CounterComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :count
  action :increment
  action :decrement
  action :set, params: { count: :integer }
  action :reset_with_flash
  action :bump_via_morph

  def initialize(count: 0)
    @count = count
  end

  def id = 'counter'

  def increment = @count += 1
  def decrement = @count -= 1
  def set(count:) = @count = count

  # Reply: replace self (token refresh) + append a flash.
  def reset_with_flash
    @count = 0
    reply.replace.flash(:notice, 'Reset')
  end

  # Reply: morph the element in place so a focused control would keep focus.
  def bump_via_morph
    @count += 1
    reply.morph
  end

  def view_template
    div(**reactive_root(class: 'flex items-center gap-3')) do
      button(**mix(on(:decrement), class: 'btn btn-sm', data: { testid: 'dec' })) { '−' }
      span(class: 'text-2xl tabular-nums w-10 text-center',
           data: { testid: 'count' }) { @count.to_s }
      button(**mix(on(:increment), class: 'btn btn-sm', data: { testid: 'inc' })) { '+' }
      button(**mix(on(:bump_via_morph), class: 'btn btn-sm btn-ghost',
                                        data: { testid: 'bump-morph' })) { '+1 (morph)' }
      button(**mix(on(:reset_with_flash), class: 'btn btn-sm btn-ghost',
                                          data: { testid: 'reset' })) { 'reset' }
    end
  end
end
