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
      TodoItemComponent.broadcast_js_to("alerts", ops)
    end

    html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
    expect(html).to include('action="reactive:js"')
    expect(html).to include("data-reactive-ops=")
    expect(html).to include("add_class")
    expect(html).to include("has-unread")
  end

  it "accepts a target for root scoping" do
    broadcasts = capture_turbo_stream_broadcasts("alerts") do
      TodoItemComponent.broadcast_js_to("alerts", ops, target: "sidebar")
    end

    html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
    expect(html).to include('target="sidebar"')
  end

  it "rejects a focus op (broadcasting focus steals focus in every tab)" do
    focus_ops = TodoItemComponent.new(todo: Todo.new).js.focus("#field")

    expect { TodoItemComponent.broadcast_js_to("alerts", focus_ops) }
      .to raise_error(ArgumentError, /focus/)
  end

  it "rejects a focus_first op the same way" do
    focus_ops = TodoItemComponent.new(todo: Todo.new).js.focus_first("#menu")

    expect { TodoItemComponent.broadcast_js_to("alerts", focus_ops) }
      .to raise_error(ArgumentError, /focus/)
  end

  it "rejects focus even when it is mixed among allowed ops (no partial broadcast)" do
    mixed = TodoItemComponent.new(todo: Todo.new).js.add_class("#bell", "unread").focus("#field")

    expect { TodoItemComponent.broadcast_js_to("alerts", mixed) }
      .to raise_error(ArgumentError, /focus/)
  end

  it "rejects an empty op chain (a dead reactive:js broadcast is a mistake)" do
    empty = TodoItemComponent.new(todo: Todo.new).js

    expect { TodoItemComponent.broadcast_js_to("alerts", empty) }
      .to raise_error(ArgumentError, /no ops/)
  end

  # Transport opts (exclude:/visible_to:) pass through broadcast_transport_opts
  # to the stream — the pgbus SSE dispatcher reads them; Action Cable ignores
  # them. We assert the call threads them through (the same contract every other
  # broadcast_*_to method upholds), so the pgbus-present path suppresses the
  # actor's own echo and the pgbus-absent path is unaffected.
  describe "transport opts pass-through (pgbus-present vs pgbus-absent)" do
    it "forwards exclude: to Turbo::StreamsChannel.broadcast_action_to" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)

      TodoItemComponent.broadcast_js_to("alerts", ops, exclude: "conn-actor-1")

      expect(Turbo::StreamsChannel).to have_received(:broadcast_action_to)
        .with("alerts", hash_including(action: "reactive:js", exclude: "conn-actor-1"))
    end

    it "forwards visible_to: when given" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)

      TodoItemComponent.broadcast_js_to("alerts", ops, visible_to: "user:7")

      expect(Turbo::StreamsChannel).to have_received(:broadcast_action_to)
        .with("alerts", hash_including(visible_to: "user:7"))
    end

    it "omits transport opts entirely when none given (pgbus-absent path unchanged)" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)

      TodoItemComponent.broadcast_js_to("alerts", ops)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_action_to) do |*, **kwargs|
        expect(kwargs).not_to have_key(:exclude)
        expect(kwargs).not_to have_key(:visible_to)
      end
    end
  end

  it "still broadcasts to the stream when no transport opts are passed (real transport)" do
    expect do
      capture_turbo_stream_broadcasts("alerts") do
        TodoItemComponent.broadcast_js_to("alerts", ops)
      end
    end.not_to raise_error
  end
end
