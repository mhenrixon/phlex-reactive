# frozen_string_literal: true

require "rails_helper"

# Issue #114: the endpoint reads turbo-stream SEMANTICS structurally off a
# Phlex::Reactive::Stream value object instead of regex-sniffing the markup it
# just built. These specs lock the NEW guarantees the refactor must hold beyond
# the pre-existing #30/#44/#46/#50 request pins (which stay green unchanged):
#   * string interop — a Stream renders through a real controller + interpolates
#     html_safe (the PUBLIC-API contract that forced the SafeBuffer subclass);
#   * byte-identity — `render turbo_stream: [Stream, raw]` is byte-identical to
#     the pre-refactor array output (a gem-upgrade pin on the String#<< contract);
#   * the builders genuinely emit Streams end-to-end (the structural path is
#     actually exercised, not silently falling through to the legacy regex).
RSpec.describe "Structured Stream value object (issue #114)", type: :request do
  let(:todo) { Todo.create!(title: "structural", done: false) }

  describe "string interop — a Stream IS an html_safe String" do
    it "the class builders return Phlex::Reactive::Stream instances" do
      stream = CounterComponent.replace(count: 3)
      expect(stream).to be_a(Phlex::Reactive::Stream)
      expect(stream).to be_a(ActiveSupport::SafeBuffer)
      expect(stream.html_safe?).to be(true)
      expect(stream.rx_action).to eq("replace")
      expect(stream.rx_target).to eq("counter")
    end

    it "the instance builders return Phlex::Reactive::Stream instances" do
      # A fresh instance per call — a Phlex component may only render once.
      expect(CounterComponent.new(count: 1).to_stream_replace).to be_a(Phlex::Reactive::Stream)
      expect(CounterComponent.new(count: 1).to_stream_replace(morph: true)).to be_a(Phlex::Reactive::Stream)
      expect(CounterComponent.new(count: 1).to_stream_update).to be_a(Phlex::Reactive::Stream)
      expect(CounterComponent.new(count: 1).to_stream_remove).to be_a(Phlex::Reactive::Stream)
      expect(CounterComponent.new(count: 1).to_stream_token).to be_a(Phlex::Reactive::Stream)
    end

    it "a Stream renders through render turbo_stream: unchanged (public-API drop-in)" do
      # ActionController's turbo_stream renderer + Rack body assembly only call
      # String#<< / #to_str on each element — a SafeBuffer subclass splices in
      # byte-for-byte. This drives it through the real dummy controller.
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "increment")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('<turbo-stream action="replace"')
      expect(response.body).to include('target="counter"')
    end

    it "interpolates into another string as html_safe bytes" do
      stream = CounterComponent.replace(count: 2)
      combined = "<div>#{stream}</div>"
      expect(combined).to start_with("<div><turbo-stream")
      expect(combined).to include('action="replace"')
    end
  end

  describe "byte-identity — the wire is unchanged (gem-upgrade pin)" do
    it "an array of a Stream + a raw string assembles byte-identically" do
      stream = CounterComponent.replace(count: 5)
      raw = %(<turbo-stream action="append" target="flash"><template>x</template></turbo-stream>).html_safe

      resp = ActionDispatch::Response.new
      resp.body = [stream, raw]

      expect(resp.body).to eq(stream.to_s + raw.to_s)
    end
  end

  describe "the structural path is genuinely exercised" do
    # bump_with_self_stream: the reply's own streams ALREADY include a
    # self-replace (a Stream at the actor's target carrying the token), so the
    # endpoint must NOT append a second token stream — proven structurally.
    it "does not double the token when the reply already self-renders (bump_with_self_stream)" do
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "bump_with_self_stream")

      expect(response).to have_http_status(:ok)
      expect(response.body.scan('target="counter"').size).to eq(1)
      expect(response.body).to include("data-reactive-token-value")
      expect(response.body).not_to include('action="reactive:token"') # no appended token stream
    end

    # bump_with_sibling: the reply streams a DIFFERENT component's replace (its
    # own token, a different target) — the endpoint must STILL refresh THIS
    # component's token (target-scoped structural dedupe, issue #30).
    it "still refreshes the actor's token when the reply streams a sibling (bump_with_sibling)" do
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "bump_with_sibling")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="reactive:token"')
      expect(response.body).to include('target="counter"')
    end

    # bump_with_js (reply.morph.js): the morph re-renders the root and carries the
    # token, so GUARD 2 finds it and injects NO fallback self-replace. The
    # reactive:js stream also targets the root (its ops scope there) but its
    # action is reactive:js — NOT a self-render — so it never counts as the token
    # refresh and no reactive:token is appended. Exactly ONE render stream (the
    # morph replace); the js stream carries no rendered body.
    it "does not let a reactive:js stream count as the token refresh (bump_with_js)" do
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "bump_with_js")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="reactive:js"')
      expect(response.body).to include('action="replace"') # the morph
      expect(response.body).to include('method="morph"')
      expect(response.body).to include("data-reactive-token-value") # the morph carries the token
      expect(response.body.scan('action="replace"').size).to eq(1) # not doubled with a fallback replace
      expect(response.body).not_to include('action="reactive:token"') # morph already refreshed it
    end
  end

  describe "raw strings still take the legacy fallback path" do
    # bump_via_partial replies with a RAW turbo-stream String (reply.streams
    # "<...>") — not a Stream. The endpoint must recognize it lacks the actor's
    # token and append the token-only refresh via the legacy path.
    it "appends the token-only refresh for a raw reply.streams string (bump_via_partial)" do
      post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_via_partial")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('target="counter-mirror"') # the raw caller stream
      expect(response.body).to include('action="reactive:token"') # legacy path appended the token
      expect(response.body).to include('target="counter"')
      expect(response.body).not_to include('action="replace"')
    end
  end
end
