# frozen_string_literal: true

require "zeitwerk"
require "globalid"

module Phlex
  # phlex-reactive: reactive Phlex components for Rails.
  #
  # Two cooperating mixins, one client runtime, one endpoint:
  #
  #   * Phlex::Reactive::Streamable — gives a component a stable `id` and class
  #     methods to render itself as a Turbo Stream (`.replace`, `.append`, ...)
  #     and to broadcast itself (`.broadcast_replace_to`, ...). The server->client
  #     half (controller responses + background broadcasts).
  #
  #   * Phlex::Reactive::Component — declares client-invokable `action`s and
  #     emits a signed identity token + the wiring the generic `reactive`
  #     Stimulus controller needs. The client->server half (clicks, form input).
  #
  # Both halves converge on ONE re-render unit: the component, targeted by its
  # `id`. See the README for the mental model and examples.
  module Reactive
    class Error < StandardError; end

    # Raised when a signed identity token fails verification (tampered, expired,
    # or signed with a different key).
    class InvalidToken < Error; end

    # Purpose string bound into every identity token's signature so a token
    # minted for phlex-reactive can't be replayed against another verifier use.
    IDENTITY_PURPOSE = "phlex-reactive/identity"

    class << self
      # The message verifier used to sign/verify component identity tokens.
      # Defaults to a purpose-scoped verifier derived from secret_key_base.
      # Override to use a dedicated key.
      attr_writer :verifier

      # The controller class used to render components with a full Rails view
      # context (url helpers, CSRF, i18n) during re-renders and broadcasts.
      # Defaults to ActionController::Base. Set to your ApplicationController if
      # components rely on app-level helpers or Current attributes.
      attr_writer :renderer

      # The controller the reactive ActionsController inherits from, given as a
      # String (resolved lazily to avoid load-order issues). Defaults to
      # "ActionController::Base"; set to "ApplicationController" to inherit your
      # app's auth/CSRF/Current. If you do, ensure the action path isn't
      # force-redirected for logged-out users when you have public components.
      attr_writer :base_controller_name

      # Exception classes the action endpoint renders as 403. Append your
      # authorization library's error (Pundit::NotAuthorizedError,
      # ActionPolicy::Unauthorized, ...).
      attr_accessor :authorization_errors

      # The path the action endpoint is mounted at. Default "/reactive/actions".
      # Set before boot if it collides with an app route. The client runtime
      # reads it from a <meta name="phlex-reactive-action-path"> tag if present,
      # falling back to this default.
      attr_writer :action_path

      def action_path
        @action_path ||= "/reactive/actions"
      end

      def verifier
        @verifier ||= default_verifier
      end

      def renderer
        @renderer ||= defined?(::ActionController::Base) ? ::ActionController::Base : nil
      end

      def base_controller_name
        @base_controller_name ||= "ActionController::Base"
      end

      def base_controller
        base_controller_name.constantize
      end

      # Returns the verified payload hash, or nil if the token is invalid.
      def verify(token)
        verifier.verified(token, purpose: IDENTITY_PURPOSE)
      end

      # Signs a payload hash into an identity token.
      def sign(payload)
        verifier.generate(payload, purpose: IDENTITY_PURPOSE)
      end

      private

      def default_verifier
        unless defined?(::Rails) && ::Rails.application
          raise Error, "Phlex::Reactive.verifier is unset and Rails.application is unavailable; " \
                       "set Phlex::Reactive.verifier = ActiveSupport::MessageVerifier.new(secret)"
        end

        ::Rails.application.message_verifier(IDENTITY_PURPOSE)
      end
    end

    self.authorization_errors = []
  end
end

loader = Zeitwerk::Loader.new
loader.tag = "phlex-reactive"
loader.push_dir(File.expand_path("..", __dir__))
loader.ignore("#{__dir__}/../phlex-reactive.rb")
loader.do_not_eager_load("#{__dir__}/reactive/engine.rb")
loader.setup

require "phlex/reactive/engine" if defined?(::Rails::Engine)
