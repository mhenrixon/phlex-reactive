# frozen_string_literal: true

module Views
  module Examples
    # A labelled checkbox that turns the client latency simulator on/off for the
    # whole tab. On a localhost round trip (~5 ms) the loading/optimistic
    # affordances — `busy:` label swaps, the `busy_on` spinner, an
    # `optimistic:` flip-then-reconcile — flash by too fast to see. Flip this on
    # and every reactive action is delayed client-side, so those affordances
    # become observable. It's a pure client concern: no reactive token, no POST.
    #
    # Drop it above any live example that demonstrates a pending/optimistic state.
    #
    #   render Views::Examples::LatencyToggle.new                # 400 ms default
    #   render Views::Examples::LatencyToggle.new(delay_ms: 800) # slower, for a longer look
    class LatencyToggle < Phlex::HTML
      def initialize(delay_ms: 400)
        @delay_ms = delay_ms
      end

      def view_template
        label(class: 'not-prose my-4 flex w-fit cursor-pointer items-center gap-3 ' \
                     'rounded-box border border-base-300 bg-base-200 px-4 py-2',
              data: { testid: 'latency-toggle' }) do
          input(
            type: 'checkbox',
            class: 'toggle toggle-sm toggle-primary',
            data: {
              testid: 'latency-toggle-input',
              controller: 'latency-toggle',
              latency_toggle_ms_value: @delay_ms,
              action: 'change->latency-toggle#toggle'
            }
          )
          span(class: 'flex flex-col') do
            span(class: 'text-sm font-medium') { 'Simulate network latency' }
            span(class: 'text-xs opacity-60') do
              plain "Delay every action by #{@delay_ms} ms so the loading states are visible."
            end
          end
        end
      end
    end
  end
end
