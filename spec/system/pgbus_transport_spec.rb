# frozen_string_literal: true

require "system_helper"

# Issue #187: the pgbus transport, verified over REAL SSE (not doubles). These
# specs run ONLY in the pgbus cells (TRANSPORT=pgbus + a Postgres service); the
# :pgbus tag + the guard below skip them everywhere else. They prove what the
# unit doubles can't: a broadcast rendered by one session is delivered to a
# SECOND session over pgbus's Postgres-backed SSE, and the actor's own echo is
# suppressed by exclude: reactive_connection_id.
#
# pgbus streams are EPHEMERAL (LISTEN/NOTIFY, live-only) — a broadcast reaches
# only subscribers CONNECTED at broadcast time. So delivery is only observable
# across live browser sessions, which is exactly the property under test. The
# :pgbus tag also flips off transactional fixtures (rails_helper.rb) so the
# actor's write COMMITS and the transactional NOTIFY actually fires.
RSpec.describe "pgbus transport (real SSE)", :pgbus, type: :system do
  before do
    skip "pgbus transport cell only (TRANSPORT=pgbus)" unless ENV["TRANSPORT"] == "pgbus"
  end

  # Wait until the room's <pgbus-stream-source> has a connection-id — i.e. the
  # SSE stream is actually OPEN. Broadcasting before it connects would race
  # (ephemeral delivery only reaches live subscribers).
  def wait_for_sse_connection
    expect(page).to have_css("pgbus-stream-source", visible: :all, wait: 10)
    expect(page).to(
      have_css("pgbus-stream-source[connection-id]", visible: :all, wait: 10),
      "the pgbus SSE stream never opened (no connection-id) — the client failed to connect"
    )
    # The connection-id attribute lands on the client the instant the SSE handshake
    # returns, but the server-side subscriber registration the broadcast's exclude:
    # matches against settles a beat later. Give it that beat so an actor's own
    # exclusion is deterministic (without this, a just-connected actor can still
    # receive its own broadcast — the exclude has no registered subscriber to skip).
    sleep 0.5
  end

  it "delivers a broadcast from one session to a SECOND session over SSE" do
    # Session 2 (observer) subscribes and connects first.
    Capybara.using_session(:observer) do
      visit "/chat"
      expect(page).to have_css("#chat-messages-lobby")
      wait_for_sse_connection
    end

    # Session 1 (actor) sends a message via the reactive action.
    Capybara.using_session(:actor) do
      visit "/chat"
      wait_for_sse_connection
      find("[data-testid='chat-input']").set("delivered over pgbus sse")
      find("[data-testid='chat-send']").click
      expect(page).to have_field("body", with: "") # round trip completed
    end

    # Session 2 receives it over SSE — the delivery the test-cable adapter
    # couldn't assert (spec/system/chat_spec.rb documents that gap).
    Capybara.using_session(:observer) do
      expect(page).to have_css("[data-testid='message']", text: "delivered over pgbus sse", wait: 10)
    end
  end

  it "suppresses the actor's own echo (exclude: reactive_connection_id)" do
    # The actor's POST carries X-Pgbus-Connection (the reactive client reads it
    # off the connected <pgbus-stream-source>), and send_message broadcasts with
    # exclude: reactive_connection_id. The composer's reply re-renders only the
    # composer (not the list), so the message reaches a client ONLY via the
    # broadcast. Therefore, with the actor excluded: the actor sees NONE of its
    # own message, while a SEPARATE observer (a different, non-excluded
    # connection) receives it. A broken exclude would echo it back to the actor.
    Capybara.using_session(:observer) do
      visit "/chat"
      expect(page).to have_css("#chat-messages-lobby")
      wait_for_sse_connection
    end

    Capybara.using_session(:actor) do
      visit "/chat"
      wait_for_sse_connection
      # Prove the connection id is actually threaded (the exclude has a real
      # target) — not a no-op that happens to look right.
      connection_id = page.evaluate_script(
        "document.querySelector('pgbus-stream-source')?.getAttribute('connection-id')"
      )
      expect(connection_id).to be_a(String).and(be_present)

      find("[data-testid='chat-input']").set("no echo to me")
      find("[data-testid='chat-send']").click
      expect(page).to have_field("body", with: "")
    end

    # The observer (NOT excluded) receives it — proving the broadcast fired.
    Capybara.using_session(:observer) do
      expect(page).to have_css("[data-testid='message']", text: "no echo to me", wait: 10)
    end

    # The actor NEVER sees its own message — its connection was excluded. By now
    # the observer already has it, so any echo to the actor would have landed.
    Capybara.using_session(:actor) do
      expect(page).to have_no_css("[data-testid='message']", text: "no echo to me")
    end
  end
end
