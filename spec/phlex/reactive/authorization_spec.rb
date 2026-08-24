# frozen_string_literal: true

require "rails_helper"

# verify_authorized (issue #168) is the presence-side complement to
# authorization_errors: a default-ON runtime guard that raises when an action
# completes WITHOUT any authorization call, rolling back the transaction
# (fail-closed). This spec covers the tracking primitive (fiber-local, Falcon-
# safe, mirroring with_connection_id), the interception (a prepend that marks the
# tracking cell only on a non-raising return of a configured authorization
# method), and the config surface (defaults + defined?-guard).
RSpec.describe Phlex::Reactive::Authorization do
  # Save and RESTORE the config across every example — the dummy sets
  # verify_authorized = false globally in its initializer, so removing the ivar
  # would re-default it to true and leak into later request specs. We snapshot
  # whatever was configured (ivar present or not) and put it back exactly.
  around do
    saved = %i[@verify_authorized @authorization_methods].to_h do
      present = Phlex::Reactive.instance_variable_defined?(it)
      [it, [present, (Phlex::Reactive.instance_variable_get(it) if present)]]
    end
    it.run
  ensure
    saved.each do |ivar, (present, value)|
      if present
        Phlex::Reactive.instance_variable_set(ivar, value)
      elsif Phlex::Reactive.instance_variable_defined?(ivar)
        Phlex::Reactive.remove_instance_variable(ivar)
      end
    end
  end

  describe ".with_tracking / .marked? / .mark!" do
    it "is untracked outside a tracking window" do
      expect(described_class.marked?).to be(false)
    end

    it "reports unmarked inside a fresh tracking window" do
      described_class.with_tracking do
        expect(described_class.marked?).to be(false)
      end
    end

    it "reports marked after mark! within the window" do
      described_class.with_tracking do
        described_class.mark!
        expect(described_class.marked?).to be(true)
      end
    end

    it "restores the previous tracking cell after the window (save/restore)" do
      described_class.with_tracking do
        described_class.mark!
      end
      # Outside, the cell is back to its pre-window state (nil).
      expect(described_class.marked?).to be(false)
    end

    it "isolates a nested window and restores the outer cell (nesting)" do
      described_class.with_tracking do
        described_class.mark!
        expect(described_class.marked?).to be(true)

        described_class.with_tracking do
          # Fresh inner window — the outer mark must NOT leak in.
          expect(described_class.marked?).to be(false)
          described_class.mark!
          expect(described_class.marked?).to be(true)
        end

        # The outer mark survives the inner window's restore.
        expect(described_class.marked?).to be(true)
      end
    end

    it "restores the cell even when the block raises" do
      expect do
        described_class.with_tracking do
          described_class.mark!
          raise "boom"
        end
      end.to raise_error("boom")
      expect(described_class.marked?).to be(false)
    end
  end

  describe ".instrument! (prepend that marks on a non-raising auth call)" do
    let(:klass) do
      Class.new do
        attr_reader :calls

        def initialize = (@calls = [])

        def authorize!(*)
          @calls << :authorize!
          :ok
        end

        def act_authorized
          authorize!(:thing)
          :done
        end

        def act_unauthorized = :done
      end
    end

    before { Phlex::Reactive.authorization_methods = %i[authorize!] }

    it "marks the tracking cell when a wrapped authorization method returns" do
      described_class.instrument!(klass)
      instance = klass.new
      described_class.with_tracking do
        instance.act_authorized
        expect(described_class.marked?).to be(true)
      end
    end

    it "does NOT mark when the action calls no authorization method" do
      described_class.instrument!(klass)
      instance = klass.new
      described_class.with_tracking do
        instance.act_unauthorized
        expect(described_class.marked?).to be(false)
      end
    end

    it "does NOT mark when the authorization method RAISES (a denial still propagates)" do
      Phlex::Reactive.authorization_methods = %i[deny!]
      raising = Class.new do
        def deny! = raise(ArgumentError, "denied")
      end
      described_class.instrument!(raising)
      described_class.with_tracking do
        expect { raising.new.deny! }.to raise_error(ArgumentError)
        expect(described_class.marked?).to be(false)
      end
    end

    it "wraps a PRIVATE authorization method too (marks on a non-raising private call)" do
      Phlex::Reactive.authorization_methods = %i[check]
      klass2 = Class.new do
        def check = :ok
        private :check

        def act
          check
          :done
        end
      end
      described_class.instrument!(klass2)
      described_class.with_tracking do
        klass2.new.act
        expect(described_class.marked?).to be(true)
      end
    end

    it "is idempotent per class object (double instrument! prepends once)" do
      described_class.instrument!(klass)
      first = klass.ancestors.length
      described_class.instrument!(klass)
      expect(klass.ancestors.length).to eq(first)
    end

    it "runs the wrapped method exactly once even when double-instrumented" do
      described_class.instrument!(klass)
      described_class.instrument!(klass)
      instance = klass.new
      described_class.with_tracking { instance.act_authorized }
      expect(instance.calls).to eq([:authorize!])
    end
  end

  describe "config surface" do
    # The booted dummy sets verify_authorized = false in its initializer, so the
    # UNCONFIGURED default is only observable with the ivar removed (the around
    # block restores it afterward).
    it "defaults verify_authorized to true when unconfigured" do
      Phlex::Reactive.remove_instance_variable(:@verify_authorized) if
        Phlex::Reactive.instance_variable_defined?(:@verify_authorized)
      expect(Phlex::Reactive.verify_authorized).to be(true)
    end

    it "honors an explicit false via the defined?-guard (not ||=)" do
      Phlex::Reactive.verify_authorized = false
      expect(Phlex::Reactive.verify_authorized).to be(false)
    end

    it "defaults authorization_methods to the common set" do
      Phlex::Reactive.remove_instance_variable(:@authorization_methods) if
        Phlex::Reactive.instance_variable_defined?(:@authorization_methods)
      expect(Phlex::Reactive.authorization_methods).to contain_exactly(:authorize!, :authorize, :allowed_to?)
    end
  end

  describe ".verify! (the enforcement decision)" do
    let(:component_class) do
      Class.new do
        def self.name = "Phlex::Reactive::AuthorizationSpec::Widget"
      end
    end
    let(:action_def) { Phlex::Reactive::Component::ActionDefinition.new(name: :save, params: {}, schema: nil) }

    it "raises AuthorizationNotVerified when on, not skipped, and unmarked" do
      Phlex::Reactive.verify_authorized = true
      described_class.with_tracking do
        expect { described_class.verify!(component_class, action_def) }
          .to raise_error(Phlex::Reactive::AuthorizationNotVerified, /save/)
      end
    end

    it "is a no-op when marked" do
      Phlex::Reactive.verify_authorized = true
      described_class.with_tracking do
        described_class.mark!
        expect { described_class.verify!(component_class, action_def) }.not_to raise_error
      end
    end

    it "is a no-op when verify_authorized is off" do
      Phlex::Reactive.verify_authorized = false
      described_class.with_tracking do
        expect { described_class.verify!(component_class, action_def) }.not_to raise_error
      end
    end

    it "is a no-op when the action is skipped" do
      Phlex::Reactive.verify_authorized = true
      skipping = Class.new do
        def self.name = "Phlex::Reactive::AuthorizationSpec::Skipped"
        def self.skip_verify_authorized?(_name) = true
      end
      described_class.with_tracking do
        expect { described_class.verify!(skipping, action_def) }.not_to raise_error
      end
    end
  end
end
