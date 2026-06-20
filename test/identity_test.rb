# frozen_string_literal: true

require "test_helper"

class IdentityTest < Minitest::Test
  def test_sign_and_verify_round_trip
    payload = { "c" => "Demo::Counter", "s" => { "count" => 3 } }
    token = Phlex::Reactive.sign(payload)
    assert_equal payload, Phlex::Reactive.verify(token)
  end

  def test_tampered_token_is_rejected
    token = Phlex::Reactive.sign({ "c" => "Demo::Counter", "s" => { "count" => 1 } })
    assert_nil Phlex::Reactive.verify(token + "x")
  end

  def test_token_from_a_different_verifier_is_rejected
    other = ActiveSupport::MessageVerifier.new("different-secret")
    forged = other.generate({ "c" => "Evil" }, purpose: Phlex::Reactive::IDENTITY_PURPOSE)
    assert_nil Phlex::Reactive.verify(forged)
  end

  def test_wrong_purpose_is_rejected
    # A token signed with the same key but a different purpose must not verify.
    token = Phlex::Reactive.verifier.generate({ "c" => "X" }, purpose: "some-other-purpose")
    assert_nil Phlex::Reactive.verify(token)
  end
end
