# frozen_string_literal: true

module Phlex
  module Reactive
    module Component
      # Lazy initial mount (issue #165): a `reactive_lazy` component's FIRST
      # (page-embedded) render emits a placeholder SHELL — the root id, the
      # generic controller, the pending markers, and a defer token ON the root
      # — and the client fetches the real content through the same defer
      # machinery on connect (the Livewire #[Lazy] shape).
      #
      # Lazy applies ONLY to the initial mount. Every render that goes through
      # the reactive machinery — an action reply's self-replace, a broadcast,
      # the defer endpoint/job, the class stream builders — runs inside
      # Defer.with_real_render, so it renders the REAL template. Anything else
      # would make an action on a lazy component cost two round trips.
      module Lazy
        extend ActiveSupport::Concern

        private

        # Phlex 2's render hook: the template runs inside the block. Overridden
        # (not yield-then-decorate) so the lazy shell can REPLACE the template
        # entirely on the initial mount. A component's own around_template
        # override composes via normal method lookup as long as it calls super.
        def around_template(&)
          klass = self.class
          if klass.respond_to?(:reactive_lazy?) && klass.reactive_lazy? && !Phlex::Reactive::Defer.real_render?
            render_defer_shell
          else
            super
          end
        end

        # The shell: owns the component's id (the arrival replaces it by that
        # id), mounts the generic controller, and carries the defer token as a
        # ROOT attribute — the controller's connect() probes it and enters the
        # same module-level fetch path a reply directive uses. Pending markers
        # + the .reactive-defer-placeholder class are the CSS hooks.
        def render_defer_shell
          div(
            id:,
            class: "reactive-defer-placeholder",
            aria: { busy: "true" },
            data: {
              controller: "reactive",
              reactive_defer_pending: "true",
              reactive_defer_token: Phlex::Reactive.sign_defer(reactive_identity_payload)
            }
          ) { render_deferred_placeholder_content }
        end

        # Same content contract as reply.defer's placeholder: true — the
        # component's deferred_placeholder returns a Phlex component instance
        # (rendered), an html_safe String (raw), or a plain String (escaped
        # text — data, not markup). No method / nil → the empty shell.
        def render_deferred_placeholder_content
          return unless respond_to?(:deferred_placeholder, true)

          value = send(:deferred_placeholder)
          case value
          when nil then nil
          when ::Phlex::SGML then render(value)
          else
            value.html_safe? ? raw(value) : plain(value.to_s)
          end
        end
      end
    end
  end
end
