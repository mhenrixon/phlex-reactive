# frozen_string_literal: true

require "rails_helper"

# Issue #233: Phlex::Kit's LazyLoader resolves a kit component call through the
# CALLING class's constant lookup (`mod.constants.include?(name) &&
# mod.const_get(name)`). Any bare-noun constant our mixins put into a reactive
# component's ancestry shadows a host kit component of the same name — the kit
# class never autoloads and the call dies with NoMethodError, but ONLY under
# lazy autoloading (dev), so it ships past an eager-loaded green suite.
#
# `Action` was exactly that (a very natural kit name — a link/button unifier).
# It is renamed ActionDefinition to match its siblings; this spec pins the
# rename AND guards the whole ancestry against the constant coming back.
RSpec.describe "kit constant shadowing (issue #233)" do # rubocop:disable RSpec/DescribeClass
  let(:klass) do
    Class.new(Phlex::HTML) do
      include Phlex::Reactive::Component

      def self.name = "KitShadowThing"

      reactive_state :count
      action :increment
      def initialize(count: 0) = @count = count
      def id = "kit-shadow"
    end
  end

  it "does not expose :Action anywhere in a component's constant lookup" do
    # The exact leg Phlex::Kit's LazyLoader checks before autoloading the real
    # kit component — if this is true, the host's kit `Action` is shadowed.
    expect(klass.constants).not_to include(:Action)
  end

  it "no longer defines the old constant on the mixin" do
    expect(Phlex::Reactive::Component.const_defined?(:Action)).to be(false)
  end

  it "stores declared actions as ActionDefinition (named like its siblings)" do
    expect(klass.reactive_actions[:increment]).to be_a(Phlex::Reactive::Component::ActionDefinition)
  end
end
