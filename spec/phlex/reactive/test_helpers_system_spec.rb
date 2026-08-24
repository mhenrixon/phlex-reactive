# frozen_string_literal: true

require "rails_helper"
# Capybara is `require: false` (a dev/test dep only system_helper.rb loads), so a
# plain unit spec run in isolation would not have it — require it here so THIS
# spec can assert the gate regardless of load order, then re-run the conditional
# require the gem ships (idempotent) to load the module under Capybara.
require "capybara"
require "phlex/reactive/test_helpers/system"

# The Capybara-gated system helpers (issue #201): wait_for_reactive + the
# re-resolving value/text matchers. These unit specs lock the module's WIRING —
# that it is defined once Capybara is present, exposes the public surface, and
# keeps its <html> marker in lockstep with the client's ACTIVE_ATTR. The browser
# BEHAVIOR (the helpers actually waiting on a live morph/defer) is proven by
# spec/system/reactive_activity_spec.rb.
RSpec.describe Phlex::Reactive::TestHelpers::System do
  it "is defined once Capybara is present (the optional-require gate)" do
    expect(defined?(Capybara)).to be_truthy
    # The module itself IS the described_class — its mere resolution proves the
    # optional require ran under Capybara (a fresh unit run requires it above).
    expect(described_class).to be_a(Module)
    expect(described_class.name).to eq("Phlex::Reactive::TestHelpers::System")
  end

  it "exposes the three public helpers" do
    expect(described_class.instance_method(:wait_for_reactive)).to be_a(UnboundMethod)
    expect(described_class.instance_method(:have_reactive_value)).to be_a(UnboundMethod)
    expect(described_class.instance_method(:have_reactive_text)).to be_a(UnboundMethod)
  end

  it "keeps ACTIVE_MARKER in lockstep with the client's data-reactive-active attribute" do
    # The client (reactive_controller.js) writes data-reactive-active on <html>;
    # the helper MUST wait on the same attribute name or wait_for_reactive is a
    # silent no-op. Pin the string so a client rename fails this spec loudly.
    expect(Phlex::Reactive::TestHelpers::System::ACTIVE_MARKER).to eq("data-reactive-active")

    client = Rails.root.join("public/vendor/reactive_controller.js").read
    expect(client).to include("data-reactive-active")
  end

  describe "#wait_option (the timeout convention)" do
    subject(:helper) do
      Class.new do
        include Phlex::Reactive::TestHelpers::System

        public :wait_option
      end.new
    end

    it "omits wait: when no timeout is given (Capybara's default applies)" do
      expect(helper.wait_option(nil)).to eq({})
    end

    it "folds an explicit timeout into Capybara's wait: option" do
      expect(helper.wait_option(5)).to eq(wait: 5)
    end
  end

  # The property matcher (issue #204) in isolation — a fake page returns scripted
  # evaluate_script results, so the polling / normalization / message logic is
  # covered with no browser. The matcher reads the field's live `.value` PROPERTY,
  # which is what a reducer sets on a disabled/computed output.
  describe described_class::ReactiveValueMatcher do
    # A page whose evaluate_script yields the NEXT scripted value each call, the
    # last repeating — so a test can model "blank, blank, then settles to 6".
    def fake_page(*values)
      queue = values.dup
      Object.new.tap do |o|
        # rubocop:disable-next Style/ItBlockParameter -- a stub method body, not an it-example
        o.define_singleton_method(:evaluate_script) { |*| queue.length > 1 ? queue.shift : queue.first }
      end
    end

    it "matches once the .value property settles to the expected string" do
      matcher = described_class.new("total_ro", "6", wait: 1)
      expect(matcher.matches?(fake_page(nil, nil, "6"))).to be(true)
    end

    it "stringifies a numeric expectation (a DOM .value is always a JS string)" do
      matcher = described_class.new("total", 6, wait: 1)
      expect(matcher.matches?(fake_page("6"))).to be(true)
    end

    it "normalizes a non-String result (Playwright's {} for a JS null) to 'not settled'" do
      # A missing field yields {} under Playwright; it must never equal the
      # expected String, so matches? fails within the (tiny) budget rather than
      # comparing a Hash to '6'.
      matcher = described_class.new("nope", "6", wait: 0)
      expect(matcher.matches?(fake_page({}))).to be(false)
    end

    it "does_not_match? holds as soon as the property differs (or the field is absent)" do
      matcher = described_class.new("total_ro", "999", wait: 0)
      expect(matcher.does_not_match?(fake_page("6"))).to be(true)
      expect(matcher.does_not_match?(fake_page({}))).to be(true) # absent → nil ≠ "999"
    end

    it "reports the settled value in its failure message" do
      matcher = described_class.new("total_ro", "6", wait: 0)
      matcher.matches?(fake_page("5"))
      expect(matcher.failure_message).to include("total_ro", '"6"', '"5"')
    end
  end
end
