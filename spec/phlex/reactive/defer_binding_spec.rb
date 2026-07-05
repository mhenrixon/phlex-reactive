# frozen_string_literal: true

require "rails_helper"

# Defer-token session binding (issue #165 security follow-up). The defer
# endpoint re-renders the real component, whose root carries a fresh
# NON-expiring identity (action) token — so a LEAKED defer token, replayed by
# another actor within its TTL, would hand that actor a permanent action token
# for the same identity. Binding the defer token to the minting actor closes
# the cross-actor exchange: a defer token minted under binding A fails
# verification under binding B.
#
# The binding is OPTIONAL by construction (apps with no session middleware —
# the gem's ActionController::Base default — still work): a token minted with
# NO binding verifies with no binding (today's behavior, unchanged), and the
# `authorize!`-in-the-action contract remains the real authority either way.
RSpec.describe "Phlex::Reactive defer token binding" do
  include ActiveSupport::Testing::TimeHelpers

  let(:payload) { { "c" => "CounterComponent", "s" => { "count" => 1 } } }
  let(:binding) { nil } # overridden per context

  # before/after (not around) to set the thread-local binding: around would
  # need a nested with_defer_binding block, where `it` resolves to THAT block's
  # implicit param (nil) not the example — the Style/ItBlockParameter nested
  # hazard. A plain set/reset pair is clearer here anyway.
  before { Thread.current[:phlex_reactive_defer_binding] = binding }
  after { Thread.current[:phlex_reactive_defer_binding] = nil }

  describe "unbound (no session — the ActionController::Base default)" do
    it "round-trips a token minted and verified with no binding" do
      token = Phlex::Reactive.sign_defer(payload)
      expect(Phlex::Reactive.verify_defer(token)).not_to be_nil
    end
  end

  describe "bound to a session identity" do
    let(:binding) { "session-A" }

    it "verifies within the SAME binding" do
      token = Phlex::Reactive.sign_defer(payload)
      expect(Phlex::Reactive.verify_defer(token)).not_to be_nil
    end

    it "REJECTS a token minted under a DIFFERENT binding (the leaked-token exchange)" do
      token = Phlex::Reactive.sign_defer(payload)

      Phlex::Reactive.with_defer_binding("session-B") do
        expect(Phlex::Reactive.verify_defer(token)).to be_nil
      end
    end

    it "REJECTS a token minted WITH a binding when verified with NONE (downgrade attempt)" do
      token = Phlex::Reactive.sign_defer(payload)

      Phlex::Reactive.with_defer_binding(nil) do
        expect(Phlex::Reactive.verify_defer(token)).to be_nil
      end
    end

    it "REJECTS a token minted with NO binding when verified UNDER one (upgrade attempt)" do
      unbound = Phlex::Reactive.with_defer_binding(nil) { Phlex::Reactive.sign_defer(payload) }
      expect(Phlex::Reactive.verify_defer(unbound)).to be_nil
    end

    it "still expires within the binding" do
      token = Phlex::Reactive.sign_defer(payload)
      travel(Phlex::Reactive.defer_token_ttl + 1) do
        expect(Phlex::Reactive.verify_defer(token)).to be_nil
      end
    end
  end

  describe ".defer_binding_for (the request → binding resolver)" do
    it "returns nil for a request with no session (graceful default)" do
      request = instance_double(ActionDispatch::Request, session: nil)
      expect(Phlex::Reactive.defer_binding_for(request)).to be_nil
    end

    it "derives a stable binding from the session id when present" do
      session = instance_double(ActionDispatch::Request::Session, id: "abc123")
      request = instance_double(ActionDispatch::Request, session:)
      expect(Phlex::Reactive.defer_binding_for(request)).to eq("abc123")
    end

    it "tolerates a session that raises (some stores lazily fail) — nil, never crash" do
      session = Object.new
      def session.id = raise("no store")
      request = instance_double(ActionDispatch::Request, session:)
      expect(Phlex::Reactive.defer_binding_for(request)).to be_nil
    end
  end
end
