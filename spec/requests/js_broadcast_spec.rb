# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

# Issue #97: Streamable.broadcast_js_to pushes server-side client DOM ops to
# EVERY subscriber of a stream over the SAME transport as every other broadcast
# (Turbo::StreamsChannel → Action Cable here, pgbus in a real app). It rides a
# `reactive:js` custom stream action carrying the HTML-escaped ops.
#
# The builder REJECTS focus-class ops outright: broadcasting a focus steals
# focus in every viewer's tab. Focus is an actor-reply concern (Response#js).
RSpec.describe "broadcast_js_to (issue #97)", type: :request do
  include Turbo::Broadcastable::TestHelper

  let(:ops) { TodoItemComponent.new(todo: Todo.new).js.add_class("#bell", "has-unread") }

  it "broadcasts a reactive:js stream carrying the ops to the stream" do
    broadcasts = capture_turbo_stream_broadcasts("alerts") do
      TodoItemComponent.broadcast_to("alerts", js: ops)
    end

    html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
    expect(html).to include('action="reactive:js"')
    expect(html).to include("data-reactive-ops=")
    expect(html).to include("add_class")
    expect(html).to include("has-unread")
  end

  it "accepts a target for root scoping" do
    broadcasts = capture_turbo_stream_broadcasts("alerts") do
      TodoItemComponent.broadcast_to("alerts", js: ops, target: "sidebar")
    end

    html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
    expect(html).to include('target="sidebar"')
  end

  it "rejects a focus op (broadcasting focus steals focus in every tab)" do
    focus_ops = TodoItemComponent.new(todo: Todo.new).js.focus("#field")

    expect { TodoItemComponent.broadcast_to("alerts", js: focus_ops) }
      .to raise_error(ArgumentError, /focus/)
  end

  it "rejects a focus_first op the same way" do
    focus_ops = TodoItemComponent.new(todo: Todo.new).js.focus_first("#menu")

    expect { TodoItemComponent.broadcast_to("alerts", js: focus_ops) }
      .to raise_error(ArgumentError, /focus/)
  end

  it "rejects focus even when it is mixed among allowed ops (no partial broadcast)" do
    mixed = TodoItemComponent.new(todo: Todo.new).js.add_class("#bell", "unread").focus("#field")

    expect { TodoItemComponent.broadcast_to("alerts", js: mixed) }
      .to raise_error(ArgumentError, /focus/)
  end

  it "rejects an empty op chain (a dead reactive:js broadcast is a mistake)" do
    empty = TodoItemComponent.new(todo: Todo.new).js

    expect { TodoItemComponent.broadcast_to("alerts", js: empty) }
      .to raise_error(ArgumentError, /no ops/)
  end

  # Transport opts (exclude:/visible_to:) thread to pgbus via THREAD-LOCALS (its
  # broadcast_stream_to patch reads Thread.current[:pgbus_broadcast_*]), NOT via
  # StreamsChannel kwargs (turbo-rails swallows unknown kwargs — issue #187). So
  # broadcast_js_to sets the thread-local when pgbus is present, and passes NO
  # transport kwargs to broadcast_action_to (Action Cable ignores them anyway).
  describe "transport opts thread to pgbus (pgbus-present)" do
    before { allow(Phlex::Reactive).to receive(:pgbus_streams?).and_return(true) }

    it "sets the exclude thread-local during the broadcast" do
      seen = nil
      allow(Turbo::StreamsChannel).to receive(:broadcast_action_to) do
        seen = Thread.current[:pgbus_broadcast_exclude]
      end

      TodoItemComponent.broadcast_to("alerts", js: ops, exclude: "conn-actor-1")

      expect(seen).to eq("conn-actor-1")
      expect(Thread.current[:pgbus_broadcast_exclude]).to be_nil # cleared after
    end

    it "sets the visible_to thread-local during the broadcast" do
      seen = nil
      allow(Turbo::StreamsChannel).to receive(:broadcast_action_to) do
        seen = Thread.current[:pgbus_broadcast_visible_to]
      end

      TodoItemComponent.broadcast_to("alerts", js: ops, visible_to: "user:7")

      expect(seen).to eq("user:7")
    end

    it "never passes exclude:/visible_to: as broadcast_action_to kwargs" do
      seen_kwargs = nil
      allow(Turbo::StreamsChannel).to receive(:broadcast_action_to) do |*_a, **kwargs|
        seen_kwargs = kwargs
      end

      TodoItemComponent.broadcast_to("alerts", js: ops, exclude: "conn-actor-1", visible_to: "user:7")

      expect(seen_kwargs).not_to have_key(:exclude)
      expect(seen_kwargs).not_to have_key(:visible_to)
    end
  end

  it "still broadcasts to the stream when no transport opts are passed (real transport)" do
    expect do
      capture_turbo_stream_broadcasts("alerts") do
        TodoItemComponent.broadcast_to("alerts", js: ops)
      end
    end.not_to raise_error
  end
end
