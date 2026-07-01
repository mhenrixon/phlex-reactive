# frozen_string_literal: true

# A reactive modal — open/close state lives in the signed token and toggles via
# reactive actions, so the docs demonstrate reactive context/overlay management
# with no custom JavaScript. The content is keyed from a server-side registry
# (DocModals), so the client only carries the chosen key + open flag.
#
#   render ReactiveModalComponent.new(modal: "architecture-diagram", label: "View the full picture")
class ReactiveModalComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :modal, :open, :label

  action :open_modal
  action :close_modal

  def initialize(modal:, label: 'Open', open: false)
    @modal = modal.to_s
    @label = label
    @open = open
  end

  def id = "reactive-modal-#{@modal}"

  def open_modal
    @open = true
    reply.morph
  end

  def close_modal
    @open = false
    reply.morph
  end

  def view_template
    div(**reactive_root(class: 'not-prose inline-block')) do
      trigger
      dialog if @open
    end
  end

  private

  def entry
    DocModals.find(@modal)
  end

  def trigger
    button(**mix(
      on(:open_modal),
      class: 'btn btn-sm btn-outline gap-2',
      data: { testid: "modal-open-#{@modal}" }
    )) do
      render ::Docs::Icon.new('maximize-2', class: 'size-4')
      plain @label
    end
  end

  # An open modal: a daisyUI modal box with a backdrop. Both the close button and
  # the backdrop fire the reactive close action.
  def dialog
    e = entry
    div(class: 'modal modal-open', role: 'dialog', data: { testid: "modal-#{@modal}" }) do
      div(class: 'modal-box max-w-2xl') do
        div(class: 'mb-4 flex items-center justify-between') do
          h3(class: 'text-lg font-semibold') { e&.fetch(:title, 'Details') }
          button(**mix(on(:close_modal), class: 'btn btn-sm btn-circle btn-ghost',
                                         data: { testid: "modal-close-#{@modal}" })) do
            render ::Docs::Icon.new('x', class: 'size-4')
          end
        end
        modal_body(e)
      end
      label(**mix(on(:close_modal), class: 'modal-backdrop', aria_label: 'Close'))
    end
  end

  def modal_body(entry)
    return div(class: 'opacity-60') { 'Not found.' } unless entry

    if entry[:code]
      render ::Docs::Code.new(entry[:code], lexer: entry.fetch(:lexer, :ruby), filename: entry[:filename])
    else
      p(class: 'text-base-content/80') { entry[:body] }
    end
  end
end
