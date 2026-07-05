# frozen_string_literal: true

# The reply.defer driver (issue #165) — a reps logger whose "Log set" action
# updates the cheap set count instantly and takes the expensive
# SessionTotalsComponent rollup off the actor's critical path with reply.defer.
#
#   * Log set             — keep-content default: the stale totals stay visible,
#     dimmed by the [data-reactive-defer-pending] CSS below, until the real
#     render streams in (~400 ms later).
#   * Log set (skeleton)  — placeholder: true replaces the totals with the
#     component's deferred_placeholder shell immediately.
#   * Log set (sync)      — the deliberate ANTI-example: the SAME rollup
#     rendered synchronously via also_replace, so the whole reply (set count
#     included) freezes for the 400 ms defer takes off the critical path.
class DeferDemoComponent < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :sets

  action :log_set
  action :log_set_skeleton
  action :log_set_sync

  def initialize(sets: 0)
    @sets = sets
  end

  def id = 'defer-demo'

  # Keep-content default: stale totals stay visible, marked pending.
  def log_set
    @sets += 1
    reply.streams(sets_stream).defer(SessionTotalsComponent.new(sets: @sets))
  end

  # Skeleton variant: the pending shell replaces the totals immediately.
  def log_set_skeleton
    @sets += 1
    reply.streams(sets_stream).defer(SessionTotalsComponent.new(sets: @sets), placeholder: true)
  end

  # The anti-example: the same rollup ON the critical path.
  def log_set_sync
    @sets += 1
    reply.streams(sets_stream).also_replace(SessionTotalsComponent.new(sets: @sets))
  end

  def view_template
    pending_css
    div(**reactive_root(class: 'flex flex-col gap-4')) do
      div(class: 'flex flex-wrap items-center gap-3') do
        button(**mix(on(:log_set, disable_with: 'Logging…'),
                     class: 'btn btn-sm btn-primary', data: { testid: 'log-set' })) { 'Log set' }
        button(**mix(on(:log_set_skeleton, disable_with: 'Logging…'),
                     class: 'btn btn-sm', data: { testid: 'log-set-skeleton' })) { 'Log set (skeleton)' }
        button(**mix(on(:log_set_sync, disable_with: 'Logging…'),
                     class: 'btn btn-sm btn-ghost', data: { testid: 'log-set-sync' })) { 'Log set (sync)' }
        span(class: 'text-sm opacity-70') do
          plain 'Sets: '
          span(id: 'defer-demo-sets', class: 'font-semibold tabular-nums',
               data: { testid: 'sets-count' }) { @sets.to_s }
        end
      end
      render SessionTotalsComponent.new(sets: @sets)
    end
  end

  private

  # The cheap companion stream — updates the set-count mirror instantly. The
  # reply.streams token refresh keeps this root's signed token rolling.
  def sets_stream
    %(<turbo-stream action="update" target="defer-demo-sets"><template>#{@sets}</template></turbo-stream>)
  end

  # Pure-CSS styling for the built-in pending hooks: dim stale content while a
  # deferred render is in flight; give the placeholder shell a pulsing
  # skeleton look. No Ruby toggles any of this — the markers do.
  def pending_css
    style do
      # Static CSS, no user input — Phlex safe(), not Rails html_safe.
      css = '[data-reactive-defer-pending]{opacity:.5;transition:opacity .15s ease}' \
            '.reactive-defer-placeholder{display:flex;align-items:center;min-height:3.5rem;' \
            'border-radius:var(--radius-box,.5rem);background:var(--color-base-200);' \
            'padding:.75rem 1rem;font-size:.875rem;' \
            'animation:defer-pulse 1.2s ease-in-out infinite}' \
            '@keyframes defer-pulse{50%{opacity:.35}}'
      raw(safe(css)) # rubocop:disable Rails/OutputSafety
    end
  end
end
