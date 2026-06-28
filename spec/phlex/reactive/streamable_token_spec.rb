# frozen_string_literal: true

require "rails_helper"

# Issue #30: a token-only refresh stream lets an action update PART of a
# component (its own hand-built streams) while still rolling the signed identity
# token forward — WITHOUT a full-self replace that would tear down focused
# inputs mid-typing. The primitive is Streamable#to_stream_token: a tiny
# `<turbo-stream action="reactive:token">` that carries the fresh
# data-reactive-token-value (the attribute the client's #extractToken reads) and
# is applied by an inert client action (a pure attribute write on the root — no
# node replacement, so focus + caret survive).
RSpec.describe "Streamable token-only refresh (issue #30)" do
  let(:todo) { Todo.create!(title: "t", done: false) }

  describe "#to_stream_token (instance primitive)" do
    it "emits the reactive:token custom action targeting self" do
      stream = CounterComponent.new(count: 0).to_stream_token
      expect(stream).to include('action="reactive:token"')
      expect(stream).to include('target="counter"')
    end

    it "carries a fresh signed token (the attribute the client extracts)" do
      stream = CounterComponent.new(count: 0).to_stream_token
      expect(stream).to include("data-reactive-token-value=")
    end

    # Regression for cosmos#1939: reactive_token is PRIVATE, so a token guard that
    # ignores private methods silently emits data-reactive-token-value="" — and the
    # next dispatch carrying that empty token is rejected (add-once-only). Assert the
    # value is actually present AND verifies, not just that the attribute exists.
    it "carries a NON-EMPTY token that re-verifies (not an empty attribute)" do
      stream = CounterComponent.new(count: 3).to_stream_token
      value = stream[/data-reactive-token-value="([^"]*)"/, 1]
      expect(value).to be_present
      expect(Phlex::Reactive.verify(value)).to include("c" => "CounterComponent")
    end

    it "does NOT re-render the component body (no full replace)" do
      # The whole point: it refreshes the token without rendering the children,
      # so a live <input> the user is typing into is never swapped out.
      stream = CounterComponent.new(count: 7).to_stream_token
      expect(stream).not_to include('action="replace"')
      expect(stream).not_to match(/>\s*7\s*</) # the rendered count is absent
    end

    it "works for a record-backed component (targets its dom_id)" do
      stream = TodoItemComponent.new(todo:).to_stream_token
      expect(stream).to include('action="reactive:token"')
      expect(stream).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
      expect(stream).to include("data-reactive-token-value=")
    end
  end
end
