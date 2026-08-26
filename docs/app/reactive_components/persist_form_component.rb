# frozen_string_literal: true

# Issue #239: reactive_persist — a client-only localStorage draft over the
# fields the root OWNS. A token-less ClientBindings form (no actions, no
# POST): typing is remembered across a reload and restored on the next
# connect, a reactive_show section re-evaluates from the restored value on
# first paint, the honeypot / hidden / password controls never reach storage,
# "Next step" writes a state bag via js.persist_state and "Discard" forgets
# the draft via js.persist_clear. (The docs demo has no form to submit — in a
# real form a successful Turbo submit clears the draft automatically.)
class PersistFormComponent < Phlex::HTML
  include Phlex::Reactive::ClientBindings

  reactive_scope :apply

  def reactive_values = { size: nil }

  def view_template
    div(**mix(reactive_root(id: 'persist-form', class: 'space-y-3'),
              reactive_persist(key: 'docs-apply', ttl: 1.hour, debounce: 100))) do
      input(**reactive_field(:name, type: 'text', placeholder: 'Your name', class: 'input input-bordered w-full'))
      textarea(**reactive_field(:bio, placeholder: 'Tell us about yourself', class: 'textarea textarea-bordered w-full'))
      div(class: 'flex gap-4') do
        label(class: 'label cursor-pointer gap-2') do
          input(**reactive_field(:size, type: 'radio', value: 's', class: 'radio'))
          plain 'Small'
        end
        label(class: 'label cursor-pointer gap-2') do
          input(**reactive_field(:size, type: 'radio', value: 'l', class: 'radio'))
          plain 'Large'
        end
        label(class: 'label cursor-pointer gap-2') do
          input(**reactive_field(:gift, type: 'checkbox', class: 'checkbox'))
          plain 'Gift'
        end
      end
      div(**reactive_show(if: { size: 'l' }, class: 'alert alert-info')) { 'Large surcharge applies' }
      # Never persisted: the honeypot (explicit skip), a hidden input, a password.
      input(name: 'fuckery', type: 'text', hidden: true, tabindex: '-1', **reactive_persist_skip)
      input(type: 'hidden', name: 'apply[tz]', value: 'UTC')
      input(**reactive_field(:secret, type: 'password', placeholder: 'Password (never stored)',
                                      class: 'input input-bordered w-full'))
      div(class: 'flex gap-2') do
        button(**mix(on_client(:click, js.persist_state(step: 2)), class: 'btn btn-primary btn-sm')) { 'Next step' }
        button(**mix(on_client(:click, js.persist_clear), class: 'btn btn-ghost btn-sm')) { 'Discard draft' }
      end
      p(class: 'text-sm opacity-70') { 'Type something, reload the page — the draft comes back.' }
    end
  end
end
