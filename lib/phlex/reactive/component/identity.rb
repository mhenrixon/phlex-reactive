# frozen_string_literal: true

module Phlex
  module Reactive
    module Component
      # The signed-identity half of Component (issue #115): reactive_token —
      # the payload signed into the DOM root on EVERY render — plus the
      # class-level ivar precomputation that keeps that render path
      # allocation-free.
      #
      # THE token hot path. Both memos below are bare defined?/||= fast paths
      # ON PURPOSE: a render must never pay a per-read generation compare
      # (issue #115 invariant, .claude/rules/performance.md). Coherence comes
      # from the WRITE side instead — Component::Registry.bump! sweeps these
      # memos off the declaring class and all its descendants whenever any
      # registry declaration lands (class-load-shaped, rare), so they can't go
      # stale even when an ancestor re-declares after a subclass memoized.
      module Identity
        extend ActiveSupport::Concern

        class_methods do
          # The record's instance-variable symbol (e.g. :@todo), computed once.
          # reactive_token reads it on every render; interpolating :"@#{key}" each
          # time would allocate a symbol per render. Nil when record-less.
          def reactive_record_ivar
            return @reactive_record_ivar if defined?(@reactive_record_ivar)

            @reactive_record_ivar = reactive_record_key ? :"@#{reactive_record_key}" : nil
          end

          # [string_key, ivar_symbol] pairs for the signed state, computed once.
          # reactive_token walks these every render; precomputing the "count"/:@count
          # forms avoids a String + Symbol allocation per key per render.
          def reactive_state_ivars
            @reactive_state_ivars ||= reactive_state_keys.map { [it.to_s, :"@#{it}"] }
          end
        end

        private

        # Signed identity payload: the class name plus whichever identity pieces
        # the component declares — a record GlobalID (`gid`), signed state (`s`),
        # or both. Keeping them in ONE MessageVerifier payload makes the state
        # (e.g. which column an inline_edit may write) tamper-proof alongside the
        # record. Record-only ({c, gid}) and state-only ({c, s}) shapes are
        # unchanged.
        #
        # A record that is NOT YET PERSISTED (new_record?) has no id → no GlobalID
        # (to_gid raises MissingModelIdError). A record-backed component may render
        # such a draft (an unsaved order the user is building): we OMIT gid and rely
        # on the declared state (reactive_state) as the draft seed, so the token
        # still signs cleanly and the client controller mounts. The draft is then
        # driven client-side (reactive_compute) until it's saved; once persisted, a
        # re-render signs the gid as usual. If the record is unsaved AND no state is
        # declared, the token carries just {c} — enough to mount, but with no
        # identity to round-trip, so declare reactive_state for a draft you sync.
        def reactive_token
          klass = self.class
          payload = { "c" => klass.name }

          if (record_ivar = klass.reactive_record_ivar)
            record = instance_variable_get(record_ivar)
            payload["gid"] = record.to_gid.to_s unless record.respond_to?(:persisted?) && !record.persisted?
          end

          state_ivars = klass.reactive_state_ivars
          unless state_ivars.empty?
            state = {}
            state_ivars.each { |key, ivar| state[key] = instance_variable_get(ivar).as_json }
            payload["s"] = state
          end

          Phlex::Reactive.sign(payload)
        end
      end
    end
  end
end
