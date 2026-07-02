# frozen_string_literal: true

require "rails_helper"

# Issue #81: less ceremony for the common component.
#
# 1. `include Phlex::Reactive::Component` alone now pulls in Streamable via
#    ActiveSupport::Concern's dependency mechanism (Streamable is included into
#    the base BEFORE Component — exactly the manual order the two-include form
#    established). The legacy explicit double include stays a harmless no-op.
# 2. A record-backed component (reactive_record :x) gets `#id` for free:
#    dom_id(record) via the render-context-free Streamable#dom_id. An explicit
#    `def id` always wins; state-backed and bare-Streamable classes still raise
#    NotImplementedError (a class-name default would silently collide for
#    multi-instance state-backed components).
RSpec.describe "Single include + default #id (issue #81)" do
  let(:todo) { Todo.create!(title: "t", done: false) }

  describe "single include (Component alone pulls in Streamable)" do
    let(:klass) do
      Class.new do
        include Phlex::Reactive::Component

        def self.name = "SingleIncludeThing"

        reactive_record :todo

        def initialize(todo:) = @todo = todo
      end
    end

    it "includes Streamable via Concern dependency, before Component" do
      ancestors = klass.ancestors
      expect(ancestors).to include(Phlex::Reactive::Streamable)
      # Streamable is included first, so Component sits closer to the class.
      expect(ancestors.index(Phlex::Reactive::Component))
        .to be < ancestors.index(Phlex::Reactive::Streamable)
    end

    it "provides the full Streamable surface" do
      expect(klass).to respond_to(:turbo_stream_builder)
      expect(klass).to respond_to(:broadcast_replace_to)
      expect(klass.new(todo:)).to respond_to(:to_stream_remove)
    end
  end

  describe "default #id for record-backed components" do
    let(:klass) do
      Class.new do
        include Phlex::Reactive::Component

        def self.name = "DefaultIdThing"

        reactive_record :todo

        def initialize(todo: nil) = @todo = todo
      end
    end

    it "defaults to dom_id(record)" do
      expect(klass.new(todo:).id).to eq(ActionView::RecordIdentifier.dom_id(todo))
    end

    it "lets an explicit def id win (normal method lookup)" do
      explicit = Class.new(klass) do
        def self.name = "ExplicitIdThing"

        def id = dom_id(@todo, "rich")
      end

      expect(explicit.new(todo:).id).to eq(ActionView::RecordIdentifier.dom_id(todo, "rich"))
    end

    it "raises for a nil record ivar rather than emitting a broken id" do
      expect { klass.new.id }.to raise_error(NotImplementedError, /def id/)
    end
  end

  describe "state-backed components (no default — stays a loud raise)" do
    let(:klass) do
      Class.new do
        include Phlex::Reactive::Component

        def self.name = "StateOnlyThing"

        reactive_state :count

        def initialize(count: 0) = @count = count
      end
    end

    it "still raises NotImplementedError" do
      expect { klass.new.id }.to raise_error(NotImplementedError)
    end

    it "tells you how to fix it (def id) and who gets the default (reactive_record)" do
      expect { klass.new.id }.to raise_error(NotImplementedError, /def id.*reactive_record/m)
    end
  end

  describe "a bare Streamable-only class" do
    let(:klass) do
      Class.new do
        include Phlex::Reactive::Streamable

        def self.name = "BareStreamableThing"
      end
    end

    it "still raises NotImplementedError (no Component API to default from)" do
      expect { klass.new.id }.to raise_error(NotImplementedError)
    end
  end

  describe "legacy explicit double include (harmless no-op)" do
    let(:klass) do
      Class.new do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "DoubleIncludeThing"

        reactive_record :todo

        def initialize(todo:) = @todo = todo
      end
    end

    it "appears once in the ancestry with Component in front" do
      ancestors = klass.ancestors
      expect(ancestors.count(Phlex::Reactive::Streamable)).to eq(1)
      expect(ancestors.index(Phlex::Reactive::Component))
        .to be < ancestors.index(Phlex::Reactive::Streamable)
    end

    it "still gets the record-backed default id" do
      expect(klass.new(todo:).id).to eq(ActionView::RecordIdentifier.dom_id(todo))
    end

    it "registering the class twice is idempotent" do
      expect do
        Phlex::Reactive::Streamable.register(klass)
        Phlex::Reactive::Streamable.register(klass)
      end.not_to raise_error
    end
  end
end
