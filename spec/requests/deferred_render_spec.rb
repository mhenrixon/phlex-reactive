# frozen_string_literal: true

require "rails_helper"

# The defer endpoint + the reply.defer wire (issue #165). Two halves:
#
#   * POST defer_path — the pull lane's render endpoint: verify the
#     purpose-scoped short-TTL token, rebuild the component from identity,
#     return its replace/morph stream. Fails closed exactly like the actions
#     endpoint (400 tamper/expiry/purpose-confusion, 404 gone record, 403
#     authorization) and no-ops (204) for render? false.
#   * POST action_path with an action returning reply.defer(...) — the reply
#     carries the cheap streams + the directive (AFTER them), the token refresh
#     survives, and a denied action leaks NO directive.
RSpec.describe "deferred renders", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:headers) { { "Accept" => "text/vnd.turbo-stream.html", "Content-Type" => "application/json" } }

  def post_defer(token)
    post Phlex::Reactive.defer_path, params: { token: }.to_json, headers: headers
  end

  def defer_token_for(payload)
    Phlex::Reactive.sign_defer(payload)
  end

  describe "POST defer_path (the pull lane endpoint)" do
    it "renders the component's replace stream, carrying a FRESH action token (arrives interactive)" do
      post_defer(defer_token_for({ "c" => "SlowTotalsComponent", "s" => { "value" => 7 } }))

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('<turbo-stream action="replace" target="slow-totals">')
      expect(response.body).to include(">7<")
      expect(response.body).to include("data-reactive-token-value")
      expect(response.body).not_to include('method="morph"')
    end

    it "honors the SIGNED morph mode" do
      post_defer(defer_token_for({ "c" => "SlowTotalsComponent", "s" => { "value" => 7 }, "m" => "morph" }))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('method="morph"')
    end

    it "rebuilds a RECORD-backed component from its gid" do
      todo = Todo.create!(title: "deferred", done: false)
      post_defer(defer_token_for({ "c" => "TodoItemComponent", "gid" => todo.to_gid.to_s }))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
      expect(response.body).to include("deferred")
    end

    it "404s when the record is gone (deleted while the defer was in flight)" do
      todo = Todo.create!(title: "gone", done: false)
      token = defer_token_for({ "c" => "TodoItemComponent", "gid" => todo.to_gid.to_s })
      todo.destroy!

      post_defer(token)
      expect(response).to have_http_status(:not_found)
    end

    it "rejects an ACTION token — purpose confusion is a 400, never a render" do
      post_defer(Phlex::Reactive.sign({ "c" => "SlowTotalsComponent", "s" => { "value" => 7 } }))
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects an EXPIRED defer token (the short TTL is the leak window)" do
      token = defer_token_for({ "c" => "SlowTotalsComponent", "s" => { "value" => 7 } })

      travel(Phlex::Reactive.defer_token_ttl + 1) do
        post_defer(token)
        expect(response).to have_http_status(:bad_request)
      end
    end

    it "rejects a tampered token" do
      post_defer("garbage")
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a token naming a non-reactive class" do
      post_defer(defer_token_for({ "c" => "Todo" }))
      expect(response).to have_http_status(:bad_request)
    end

    it "renders a reactive_lazy component's REAL content (the shell must never echo back)" do
      post_defer(defer_token_for({ "c" => "LazyStatsComponent", "s" => { "scope" => "week" } }))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("stats:week")
      expect(response.body).not_to include("reactive-defer-placeholder")
    end

    it "204s (clear pending, keep content) when the component's render? is false" do
      SlowTotalsComponent.suppressed = true
      post_defer(defer_token_for({ "c" => "SlowTotalsComponent", "s" => { "value" => 7 } }))

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
    ensure
      SlowTotalsComponent.suppressed = false
    end
  end

  describe "reply.defer through the actions endpoint" do
    it "emits the cheap stream + the directive, directive AFTER all render streams" do
      post_action(DeferDemoComponent, act: :bump, payload: { "s" => { "count" => 0 } })

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include('action="update" target="defer-count"')
      expect(body).to include('action="reactive:defer" target="slow-totals"')
      expect(body).to include('data-reactive-defer-via="fetch"')
      expect(body.index('action="reactive:defer"')).to be > body.index('target="defer-count"')
    end

    it "the directive's token round-trips to the DEFERRED component's identity" do
      post_action(DeferDemoComponent, act: :bump, payload: { "s" => { "count" => 0 } })

      raw = response.body[/data-reactive-defer-token="([^"]+)"/, 1]
      payload = Phlex::Reactive.verify_defer(CGI.unescapeHTML(raw))
      expect(payload["c"]).to eq("SlowTotalsComponent")
      expect(payload["s"]).to eq({ "value" => 2 })
    end

    it "still refreshes the ACTING component's token (the #30 guarantee survives defer)" do
      post_action(DeferDemoComponent, act: :bump, payload: { "s" => { "count" => 0 } })

      expect(response.body).to include('action="reactive:token" target="defer-demo"')
    end

    it "keep-content default ships NO placeholder shell" do
      post_action(DeferDemoComponent, act: :bump, payload: { "s" => { "count" => 0 } })

      expect(response.body).not_to include("reactive-defer-placeholder")
      expect(response.body).not_to include("data-reactive-defer-pending")
    end

    it "placeholder: true ships the component's shimmer shell BEFORE the directive" do
      post_action(DeferDemoComponent, act: :bump_skeleton, payload: { "s" => { "count" => 0 } })

      body = response.body
      expect(body).to include('data-reactive-defer-pending="true"')
      expect(body).to include("totals-shimmer")
      expect(body.index("data-reactive-defer-pending")).to be < body.index('action="reactive:defer"')
    end

    it "morph: true stamps the mode into the signed directive token" do
      post_action(DeferDemoComponent, act: :bump_morph, payload: { "s" => { "count" => 0 } })

      raw = response.body[/data-reactive-defer-token="([^"]+)"/, 1]
      expect(Phlex::Reactive.verify_defer(CGI.unescapeHTML(raw))["m"]).to eq("morph")
    end

    it "reply.defer with no prior verb still self-replaces (render_self guarantee)" do
      component = Class.new(ApplicationComponent) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "BareDeferComponent"
        reactive_state :n
        action :go
        def initialize(n: 0) = @n = n
        def id = "bare-defer"
        def go = reply.defer(SlowTotalsComponent.new(value: 1))
        def view_template = div(id:, **reactive_attrs) { @n.to_s }
      end
      stub_const("BareDeferComponent", component)

      post_action(component, act: :go, payload: { "s" => { "n" => 0 } })

      body = response.body
      expect(body).to include('action="replace" target="bare-defer"')
      expect(body).to include('action="reactive:defer" target="slow-totals"')
    end

    it "a DENIED action leaks no directive — the reply dies with the transaction" do
      post_action(DeferDemoComponent, act: :deny_after_defer, payload: { "s" => { "count" => 0 } })

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("reactive:defer")
    end

    it "the sync baseline (bump_sync) renders the totals INSIDE the reply — no directive" do
      post_action(DeferDemoComponent, act: :bump_sync, payload: { "s" => { "count" => 0 } })

      body = response.body
      expect(body).to include('action="replace" target="slow-totals"')
      expect(body).to include(">2<")
      expect(body).not_to include("reactive:defer")
    end
  end

  describe "the push lane over the actions endpoint (pgbus doubles + :auto)" do
    before do
      pgbus = Module.new { def self.stream(*) = nil }
      capable_stream = Class.new do
        def broadcast(payload, visible_to: nil, durable: nil, exclude: nil, event: nil,
                      coalesce: nil, target: nil)
          [payload, visible_to, durable, exclude, event, coalesce, target]
        end
      end
      stub_const("Pgbus", pgbus)
      stub_const("Pgbus::Streams", Module.new)
      stub_const("Pgbus::Streams::Stream", capable_stream)
      stub_const("Pgbus::Streams::SignedName", Module.new do
        def self.sign(name) = "signed-#{name}"
      end)
      ActiveJob::Base.queue_adapter = :test
    end

    it "emits a stream directive (src + since-id, NO token) and enqueues the render job" do
      expect do
        post_action(DeferDemoComponent, act: :bump, payload: { "s" => { "count" => 0 } })
      end.to have_enqueued_job(Phlex::Reactive::DeferredRenderJob)

      body = response.body
      expect(body).to include('data-reactive-defer-via="stream"')
      expect(body).to match(%r{data-reactive-defer-src="/pgbus/streams/signed-prdefer_\h{32}"})
      expect(body).to include('data-reactive-defer-since-id="0"')
      expect(body).not_to include("data-reactive-defer-token")
      # The cheap companion + the actor's token refresh are lane-independent.
      expect(body).to include('action="update" target="defer-count"')
      expect(body).to include('action="reactive:token" target="defer-demo"')
    end

    it "a DENIED action enqueues NO job (the rescue path drops the whole reply)" do
      expect do
        post_action(DeferDemoComponent, act: :deny_after_defer, payload: { "s" => { "count" => 0 } })
      end.not_to have_enqueued_job(Phlex::Reactive::DeferredRenderJob)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
