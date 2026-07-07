# frozen_string_literal: true

require "rails_helper"

# Issue #186: the defer endpoint emits ONE `defer.phlex_reactive` event per
# deferred render, carrying the component NAME + the outcome (never the token,
# params, or state). This CONTRACT spec freezes that payload shape — driving ALL
# FIVE outcomes — so a future rename fails CI (the same guarantee the action /
# render / broadcast payloads already have). Payload changes become additive-only.
RSpec.describe "defer.phlex_reactive instrumentation contract (issue #186)", type: :request do
  def capture_defer_events
    events = []
    sub = ActiveSupport::Notifications.subscribe("defer.phlex_reactive") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  def post_defer(token)
    post Phlex::Reactive.defer_path,
      params: { token: }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }
  end

  def defer_token_for(payload) = Phlex::Reactive.sign_defer(payload)

  it "emits :ok with the component name on a successful deferred render" do
    events = capture_defer_events do
      post_defer(defer_token_for({ "c" => "SlowTotalsComponent", "s" => { "value" => 7 } }))
    end
    expect(response).to have_http_status(:ok)
    payload = events.first.payload
    expect(payload[:component]).to eq("SlowTotalsComponent")
    expect(payload[:outcome]).to eq(:ok)
  end

  it "emits :no_content when the component suppresses its own render" do
    SlowTotalsComponent.suppressed = true
    events = capture_defer_events do
      post_defer(defer_token_for({ "c" => "SlowTotalsComponent", "s" => { "value" => 7 } }))
    end
    expect(response).to have_http_status(:no_content)
    expect(events.first.payload[:outcome]).to eq(:no_content)
  ensure
    SlowTotalsComponent.suppressed = false
  end

  it "emits :invalid_token for a tampered/garbage token (no component trusted)" do
    events = capture_defer_events { post_defer("garbage.token.value") }
    expect(response).to have_http_status(:bad_request)
    expect(events.first.payload[:outcome]).to eq(:invalid_token)
  end

  it "emits :not_found when the record vanished mid-flight" do
    todo = Todo.create!(title: "gone", done: false)
    token = defer_token_for({ "c" => "TodoItemComponent", "gid" => todo.to_gid.to_s })
    todo.destroy!
    events = capture_defer_events { post_defer(token) }
    expect(response).to have_http_status(:not_found)
    expect(events.first.payload[:outcome]).to eq(:not_found)
  end

  it "emits :unauthorized when the render raises a registered authorization error" do
    events = capture_defer_events do
      post_defer(defer_token_for({ "c" => "DeferAuthComponent", "s" => { "value" => 1 } }))
    end
    expect(response).to have_http_status(:forbidden)
    expect(events.first.payload[:outcome]).to eq(:unauthorized)
  end

  it "the payload carries NO secrets on any outcome (only component + outcome)" do
    events = capture_defer_events do
      post_defer(defer_token_for({ "c" => "SlowTotalsComponent", "s" => { "value" => 7 } }))
    end
    payload = events.first.payload
    expect(payload.keys).to contain_exactly(:component, :outcome)
    expect(payload.values.join).not_to include("value") # no state leaked
  end
end
