# frozen_string_literal: true

require "rails_helper"

# Issue #28: a morph stream re-renders a component in place via Turbo 8's
# bundled Idiomorph (`<turbo-stream action="replace" method="morph">`), which
# morphs the subtree instead of an outerHTML swap — preserving the focused
# <input> + caret while still refreshing the signed token. These specs pin the
# wire format (the `method="morph"` attribute) for the instance primitive and
# the class builder's `morph:` flag — and prove the default (no morph:) is
# byte-for-byte unchanged (backwards compat). The broadcast `morph:` flag is
# covered in spec/requests (where Turbo's broadcast test helper is wired).
RSpec.describe "Streamable morph (issue #28)" do
  # A fresh component per example: a Phlex instance can only render once, and
  # several of these stream the same component twice (once per assertion).
  let(:todo) { Todo.create!(title: "t", done: false) }

  describe "#to_stream_morph (instance primitive)" do
    it "emits a replace action with method=\"morph\" targeting self" do
      stream = CounterComponent.new(count: 0).to_stream_morph
      expect(stream).to include('action="replace"')
      expect(stream).to include('method="morph"')
      expect(stream).to include('target="counter"')
    end

    it "carries the re-rendered root (fresh signed token)" do
      stream = CounterComponent.new(count: 0).to_stream_morph
      expect(stream).to include("data-reactive-token-value=")
    end
  end

  describe "#to_stream_replace stays a plain swap (no morph attr) — back-compat" do
    it "never emits method=\"morph\"" do
      stream = CounterComponent.new(count: 0).to_stream_replace
      expect(stream).to include('action="replace"')
      expect(stream).not_to include("method=")
    end
  end

  describe ".replace(model, morph:) class builder" do
    it "adds method=\"morph\" when morph: true" do
      stream = TodoItemComponent.replace(todo, morph: true)
      expect(stream).to include('action="replace"')
      expect(stream).to include('method="morph"')
      expect(stream).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "omits method= by default (unchanged)" do
      expect(TodoItemComponent.replace(todo)).not_to include("method=")
    end
  end

  # Issue #113: the update verbs gain the same morph: flag replace already has.
  # Turbo 8 supports method="morph" on action="update", so an inner-HTML update
  # can morph in place — a cross-tab update no longer clobbers a peer's caret.
  describe "#to_stream_update (instance primitive)" do
    it "adds method=\"morph\" when morph: true" do
      stream = CounterComponent.new(count: 0).to_stream_update(morph: true)
      expect(stream).to include('action="update"')
      expect(stream).to include('method="morph"')
      expect(stream).to include('target="counter"')
    end

    it "stays a plain update (no morph attr) by default — back-compat" do
      stream = CounterComponent.new(count: 0).to_stream_update
      expect(stream).to include('action="update"')
      expect(stream).not_to include("method=")
    end
  end

  describe ".update(model, morph:) class builder" do
    it "adds method=\"morph\" when morph: true" do
      stream = TodoItemComponent.update(todo, morph: true)
      expect(stream).to include('action="update"')
      expect(stream).to include('method="morph"')
      expect(stream).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "omits method= by default (unchanged)" do
      expect(TodoItemComponent.update(todo)).not_to include("method=")
    end
  end
end
