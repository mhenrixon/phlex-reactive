# frozen_string_literal: true

require "rails_helper"

# The action endpoint emits ONE `action.phlex_reactive` ActiveSupport::Notifications
# event per request (issue #107), carrying the component/action NAMES, the
# outcome, and duration — never the token, params, or state. APM tools
# (AppSignal, Datadog, Skylight) auto-subscribe to `*.phlex_reactive` and get
# component-level visibility they had none of before.
RSpec.describe "action.phlex_reactive instrumentation", type: :request do
  # Collect every action event fired during the block.
  def capture_action_events
    events = []
    sub = ActiveSupport::Notifications.subscribe("action.phlex_reactive") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  let(:todo) { Todo.create!(title: "x") }

  it "emits :ok with the component + action names on a successful action" do
    events = capture_action_events do
      post_action(CounterComponent, act: "increment", payload: { "s" => { "count" => 1 } })
    end
    expect(response).to have_http_status(:ok)
    expect(events.size).to eq(1)
    payload = events.first.payload
    expect(payload[:component]).to eq("CounterComponent")
    expect(payload[:action]).to eq("increment")
    expect(payload[:outcome]).to eq(:ok)
    expect(events.first.duration).to be >= 0
  end

  it "emits :denied_undeclared for an undeclared action (default-deny)" do
    events = capture_action_events do
      post_action(CounterComponent, act: "drop_table", payload: { "s" => { "count" => 1 } })
    end
    expect(response).to have_http_status(:forbidden)
    expect(events.first.payload[:outcome]).to eq(:denied_undeclared)
    expect(events.first.payload[:action]).to eq("drop_table")
  end

  it "emits :invalid_token WITHOUT trusting the unverified component name" do
    events = capture_action_events do
      post "/reactive/actions",
        params: { token: "garbage.token.value", act: "increment", params: {} }.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }
    end
    expect(response).to have_http_status(:bad_request)
    payload = events.first.payload
    expect(payload[:outcome]).to eq(:invalid_token)
    # The component name comes from an UNVERIFIED token — it must NOT be reported
    # as if trusted. nil is acceptable; a truthy trusted class name is not.
    expect(payload[:component]).to be_nil
  end

  it "emits :not_found when the record vanished" do
    gid = todo.to_gid.to_s
    todo.destroy!
    events = capture_action_events do
      post_action(TodoItemComponent, act: "toggle", payload: { "gid" => gid })
    end
    expect(response).to have_http_status(:not_found)
    expect(events.first.payload[:outcome]).to eq(:not_found)
  end

  it "emits :unauthorized when the action raises a registered authorization error" do
    events = capture_action_events do
      post_action(CounterComponent, act: "boom", payload: { "s" => { "count" => 1 } })
    end
    expect(response).to have_http_status(:forbidden)
    expect(events.first.payload[:outcome]).to eq(:unauthorized)
  end

  describe "the payload never carries secrets" do
    it "has no token, params, or state key on any outcome" do
      events = capture_action_events do
        post_action(CounterComponent, act: "set",
          payload: { "s" => { "count" => 1 } }, params: { count: 99, secret: "leak" })
      end
      payload = events.first.payload
      expect(payload.keys).to contain_exactly(:component, :action, :outcome)
      # Belt-and-suspenders: no value anywhere mentions the posted secret.
      expect(payload.values.join).not_to include("leak")
      expect(payload.values.join).not_to include("99")
    end
  end
end
