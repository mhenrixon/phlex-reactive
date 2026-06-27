# frozen_string_literal: true

module Phlex
  module Reactive
    # A component-bound facade over Response — the surface an action body uses to
    # control its reply. Component#reply returns one, so an action writes
    #
    #   reply.replace.flash(:error, msg)
    #
    # instead of
    #
    #   Phlex::Reactive::Response.replace(self).flash(:error, msg)
    #
    # Two warts disappear: there is no constant to qualify (reply is a method,
    # resolved on the component — so a namespaced component needs no
    # `Response = …` alias) and no `self` to thread (the component is bound).
    #
    # Reply is NOT a Response and does NOT subclass one: each verb forwards to
    # the Response class method, supplying the bound component as the subject, and
    # returns the real, frozen Response value the endpoint already honors. So
    # immutability, chaining (.flash/.stream/.also_update/.also_replace), and
    # render_self? are inherited untouched — and there is no "verb after a chained
    # Response" asymmetry, because the chain is plain Response all the way down.
    #
    # Response remains the public value object (it's what the endpoint reads); it
    # is simply an internal detail you rarely name directly now.
    class Reply
      def initialize(component)
        @component = component
      end

      # Self-targeting builders — the bound component is supplied implicitly.

      # Re-render in place. `morph: true` morphs the subtree (preserves the
      # focused input + caret) instead of an outerHTML swap — see #morph.
      def replace(morph: false)
        Response.replace(@component, morph:)
      end

      # Re-render in place via Idiomorph (method="morph") — keeps focus + caret.
      def morph
        Response.morph(@component)
      end

      # Morph only inner HTML (preserves the root element + its token attr).
      def update
        Response.update(@component)
      end

      # Remove the component's element from the DOM (render_self false).
      def remove
        Response.remove(@component)
      end

      # Subject-free builders — pass straight through so they read naturally.

      # Client-side full navigation (Turbo.visit). Pass a *_url.
      def redirect(url)
        Response.redirect(url)
      end

      # Escape hatch / multi-stream root: zero or more raw turbo-stream strings.
      def with(*strings)
        Response.with(*strings)
      end

      # Self-targeting again: emit exactly these streams with a TOKEN-ONLY refresh
      # (issue #30) — partial/per-field update, NO full-self replace, so the
      # component's live inputs survive. The bound component supplies the token.
      def streams(*strings)
        Response.streams(@component, *strings)
      end
    end
  end
end
