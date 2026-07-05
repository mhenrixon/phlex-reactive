# frozen_string_literal: true

require "rails_helper"

# skip_verify_authorized (issue #168) is the explicit opt-out from the default-ON
# verify_authorized guard, for a component (or specific actions) that legitimately
# has no authorization — a public counter, a client-only filter. It is registry #6
# (Component::Registry), so it inherits with the SAME semantics as the other five
# registries (resolve through the superclass at read time).
RSpec.describe "skip_verify_authorized DSL" do # rubocop:disable RSpec/DescribeClass
  def component(&) = Class.new(ApplicationComponent, &)

  describe "bare skip (whole component)" do
    let(:klass) do
      component do
        include Phlex::Reactive::Component

        skip_verify_authorized
        action :bump
        action :reset
      end
    end

    it "skips every action" do
      expect(klass.skip_verify_authorized?(:bump)).to be(true)
      expect(klass.skip_verify_authorized?(:reset)).to be(true)
      # Even an action that isn't declared reads as skipped under a bare skip.
      expect(klass.skip_verify_authorized?(:anything)).to be(true)
    end
  end

  describe "named skip (specific actions only)" do
    let(:klass) do
      component do
        include Phlex::Reactive::Component

        skip_verify_authorized :filter, :page
        action :filter
        action :page
        action :destroy
      end
    end

    it "skips the named actions" do
      expect(klass.skip_verify_authorized?(:filter)).to be(true)
      expect(klass.skip_verify_authorized?(:page)).to be(true)
    end

    it "does NOT skip an action not in the list" do
      expect(klass.skip_verify_authorized?(:destroy)).to be(false)
    end
  end

  describe "no skip declared" do
    let(:klass) do
      component do
        include Phlex::Reactive::Component

        action :destroy
      end
    end

    it "skips nothing" do
      expect(klass.skip_verify_authorized?(:destroy)).to be(false)
    end
  end

  describe "inheritance (through Registry)" do
    it "inherits a bare parent skip" do
      parent = component do
        include Phlex::Reactive::Component

        skip_verify_authorized
      end
      child = Class.new(parent) { action :bump }
      expect(child.skip_verify_authorized?(:bump)).to be(true)
    end

    it "inherits a parent's named skips and unions with the child's" do
      parent = component do
        include Phlex::Reactive::Component

        skip_verify_authorized :inherited_action
      end
      child = Class.new(parent) do
        skip_verify_authorized :own_action
      end
      expect(child.skip_verify_authorized?(:inherited_action)).to be(true)
      expect(child.skip_verify_authorized?(:own_action)).to be(true)
      expect(child.skip_verify_authorized?(:other)).to be(false)
    end

    it "a child's bare skip covers everything even if the parent named only some" do
      parent = component do
        include Phlex::Reactive::Component

        skip_verify_authorized :only_this
      end
      child = Class.new(parent) { skip_verify_authorized }
      expect(child.skip_verify_authorized?(:only_this)).to be(true)
      expect(child.skip_verify_authorized?(:anything_else)).to be(true)
    end
  end
end
