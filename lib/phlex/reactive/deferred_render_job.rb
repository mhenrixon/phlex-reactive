# frozen_string_literal: true

module Phlex
  module Reactive
    # The push lane's render leg (issue #165): rebuild the deferred component
    # from its identity payload OFF the request thread, render it, and
    # broadcast the result DURABLY to the one-shot stream the actor's
    # <pgbus-stream-source> subscribes to. Durable is load-bearing: pgbus's
    # since-id replay only covers PGMQ-persisted messages, and that replay is
    # what closes the broadcast-before-subscribe race.
    #
    # Every broadcast payload ends with a remove of the client's source element
    # (id reactive-defer-src-<target>), so the subscription tears itself down
    # with the content it delivered — no client-side arrival bookkeeping.
    #
    # A gone record (deleted while the job sat in the queue) or render? false
    # broadcasts the CLEANUP instead: reactive:js ops clearing the pending
    # markers + the teardown. The shimmer must never hang, and a deleted record
    # must not retry (rescued, not retried — there is nothing to render).
    #
    # NOT eager-loaded (see the loader config in phlex/reactive.rb): the class
    # body needs ActiveJob::Base, which isn't a gem dependency — the constant
    # is only referenced behind Phlex::Reactive.defer_push_capable?.
    class DeferredRenderJob < ::ActiveJob::Base
      queue_as { Phlex::Reactive.defer_job_queue }

      def perform(component_class_name, payload, stream_key, target, morph)
        klass = component_class_name.constantize
        # Defense in depth (the args come from our own enqueue, but fail
        # closed): only reactive components may be rebuilt and rendered.
        unless klass.respond_to?(:reactive_action?) && klass.include?(Phlex::Reactive::Component)
          raise ::ArgumentError,
            "#{component_class_name} is not a reactive component — refusing the deferred render"
        end

        component = klass.from_identity(payload)
        return broadcast_cleanup(stream_key, target) if component.respond_to?(:render?) && !component.render?

        stream = morph ? component.to_stream_morph : component.to_stream_replace
        broadcast_payload(stream_key, stream.to_s + teardown_stream(target))
      rescue ActiveRecord::RecordNotFound
        broadcast_cleanup(stream_key, target)
      end

      private

      # The durable one-shot broadcast. Pgbus.stream(key, durable: true)
      # forces the PGMQ lane regardless of the app's stream default — the
      # replay guarantee depends on it.
      def broadcast_payload(stream_key, html)
        ::Pgbus.stream(stream_key, durable: true).broadcast(html)
      end

      # Nothing to render — clear the actor's pending markers (reactive:js
      # remove_attr ops, @root-scoped to the target) and tear the source down.
      def broadcast_cleanup(stream_key, target)
        ops = Phlex::Reactive::JS.new
          .remove_attr(:root, "data-reactive-defer-pending")
          .remove_attr(:root, "aria-busy")
        js = Phlex::Reactive::Response.js_stream(ops, target: target)
        broadcast_payload(stream_key, js.to_s + teardown_stream(target))
      end

      # Remove the actor's <pgbus-stream-source> by its deterministic id — the
      # client minted it as reactive-defer-src-<target>; its
      # disconnectedCallback closes the SSE connection. html_safe by
      # construction (the one interpolation is escaped) — and REQUIRED: the
      # render stream is a SafeBuffer, and `safe + plain` would HTML-escape
      # this whole tag into the payload.
      def teardown_stream(target)
        %(<turbo-stream action="remove" target="reactive-defer-src-#{ERB::Util.html_escape(target)}"></turbo-stream>)
          .html_safe
      end
    end
  end
end
