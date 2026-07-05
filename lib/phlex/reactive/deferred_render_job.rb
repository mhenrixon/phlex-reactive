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
        # closed): only reactive components may be rebuilt and rendered. This is
        # a PROGRAMMING error (a bad enqueue), not a recoverable runtime failure
        # — it raises loudly and broadcasts NOTHING, OUTSIDE the render rescue
        # below (a component with actions can't be forged past the signed
        # identity anyway, so this never fires for a real defer).
        unless klass.respond_to?(:reactive_action?) && klass.include?(Phlex::Reactive::Component)
          raise ::ArgumentError,
            "#{component_class_name} is not a reactive component — refusing the deferred render"
        end

        render_and_broadcast(klass, payload, stream_key, target, morph)
      end

      private

      # The render/broadcast leg, wrapped so ANY failure past a successful
      # enqueue (a gone record, a render raising, from_identity blowing up) still
      # resolves the actor's pending state: the stream lane has no client-side
      # timeout, so a silent job death would hang the shimmer forever. On failure
      # we broadcast the cleanup (pending-clear ops + source teardown). If that
      # cleanup broadcast SUCCEEDS the actor is unstuck and we swallow the
      # original error (a retry can't help — a re-render would raise the same way
      # and the actor already saw the content clear); a non-RecordNotFound is
      # logged for the operator. If the cleanup broadcast ITSELF fails (Postgres
      # down) there is nothing deliverable — that propagates so ActiveJob's retry
      # policy gets a chance next attempt.
      def render_and_broadcast(klass, payload, stream_key, target, morph)
        component = klass.from_identity(payload)
        return broadcast_cleanup(stream_key, target) if component.respond_to?(:render?) && !component.render?

        stream = morph ? component.to_stream_morph : component.to_stream_replace
        broadcast_payload(stream_key, stream.to_s + teardown_stream(target))
      rescue ::StandardError => e
        log_deferred_failure(e) unless e.is_a?(::ActiveRecord::RecordNotFound)
        broadcast_cleanup(stream_key, target)
      end

      # The durable one-shot broadcast. Pgbus.stream(key, durable: true)
      # forces the PGMQ lane regardless of the app's stream default — the
      # replay guarantee depends on it. We send the RAW <turbo-stream> HTML
      # string exactly as pgbus's own broadcast_render does; pgbus's SSE
      # envelope flattens newlines out of the data: line (turbo-stream HTML is
      # newline-insensitive between tags, so this is lossless for markup — the
      # same behavior as every other pgbus broadcast, not a defer-specific
      # concern). The one-shot queue is reclaimed by pgbus's orphan sweep, NOT
      # dropped here — an eager drop would destroy a not-yet-consumed message
      # and reopen the broadcast-before-subscribe race (see the README push-lane
      # note + Phlex::Reactive.defer_transport).
      def broadcast_payload(stream_key, html)
        ::Pgbus.stream(stream_key, durable: true).broadcast(html)
      end

      # Log a genuinely unexpected deferred-render failure (not the routine
      # deleted-while-queued case) so an operator sees it — the actor gets a
      # clean pending-clear regardless, which would otherwise hide the cause.
      def log_deferred_failure(error)
        return unless defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger

        ::Rails.logger.error(
          "[phlex-reactive] DeferredRenderJob failed (#{error.class}: #{error.message}) — " \
          "broadcasting cleanup so the actor's pending state resolves."
        )
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
