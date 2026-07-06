# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe "Reactive actions", type: :request do
  include Turbo::Broadcastable::TestHelper

  describe "state-backed component (CounterComponent)" do
    it "runs an action and returns an auto-targeted turbo-stream" do
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "increment")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="replace"')
      expect(response.body).to include('target="counter"')
      expect(response.body).to match(/>\s*2\s*</) # 1 -> 2
    end

    it "coerces a typed param" do
      post_action(CounterComponent, payload: { "s" => { "count" => 9 } }, act: "set", params: { count: "0" })
      expect(response.body).to match(/>\s*0\s*</)
    end

    it "forbids an undeclared action (default-deny)" do
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "destroy_everything")
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "record-backed component (TodoItemComponent)" do
    let!(:todo) { Todo.create!(title: "write specs", done: false) }

    it "re-finds the record by GlobalID and runs the action" do
      post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "toggle")

      expect(response).to have_http_status(:ok)
      expect(todo.reload.done?).to be(true)
      expect(response.body).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "returns 404 when the record no longer exists" do
      gid = todo.to_gid.to_s
      todo.destroy!
      post_action(TodoItemComponent, payload: { "gid" => gid }, act: "toggle")
      expect(response).to have_http_status(:not_found)
    end

    # Regression for issue #4: the action endpoint builds via reactive_record_key
    # (:todo) while the broadcast path used the demodulized class name
    # (:todo_item_component) — so the broadcast raised
    # `ArgumentError: missing keyword: :todo`. The component class name
    # (TodoItemComponent) differs from its reactive_record name (:todo), and it
    # carries no model_param_name override, so both paths must now agree.
    it "broadcasts a replace without raising ArgumentError (issue #4)" do
      stream = "todos"

      expect do
        broadcasts = capture_turbo_stream_broadcasts(stream) do
          TodoItemComponent.broadcast_replace_to(stream, model: todo)
        end

        html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
        expect(html).to include('action="replace"')
        expect(html).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
        expect(html).to include("write specs")
      end.not_to raise_error
    end

    # Issue #28: a live cross-tab replace can morph in place so a peer tab keeps
    # its focus/caret on the morphed row. Default broadcasts stay a plain swap.
    it "broadcasts a morphing replace when morph: true (issue #28)" do
      broadcasts = capture_turbo_stream_broadcasts("todos") do
        TodoItemComponent.broadcast_replace_to("todos", model: todo, morph: true)
      end
      html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="replace"')
      expect(html).to include('method="morph"')
    end

    it "broadcasts a plain replace (no morph attr) by default" do
      broadcasts = capture_turbo_stream_broadcasts("todos") do
        TodoItemComponent.broadcast_replace_to("todos", model: todo)
      end
      html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).not_to include("method=")
    end

    # Issue #113: broadcast_update_to gains the same morph: flag. A cross-tab
    # update into a component a peer is editing morphs in place, so the peer
    # keeps its focus/caret instead of an inner-HTML clobber. The morph flag
    # rides through `attributes:` (the broadcast path has no method: kwarg).
    # The pgbus-absent fallback (this Action Cable path) is unchanged unless
    # morph: true is asked for.
    it "broadcasts a morphing update when morph: true (issue #113)" do
      broadcasts = capture_turbo_stream_broadcasts("todos") do
        TodoItemComponent.broadcast_update_to("todos", model: todo, morph: true)
      end
      html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="update"')
      expect(html).to include('method="morph"')
    end

    it "broadcasts a plain update (no morph attr) by default" do
      broadcasts = capture_turbo_stream_broadcasts("todos") do
        TodoItemComponent.broadcast_update_to("todos", model: todo)
      end
      html = broadcasts.map(&:to_s).join # rubocop:disable Style/MapJoin
      expect(html).to include('action="update"')
      expect(html).not_to include("method=")
    end
  end

  describe "record + state component (InlineEditComponent, issue #6)" do
    let!(:todo) { Todo.create!(title: "original", done: false) }

    # Mint a token exactly as the component would after a render: it signs the
    # record gid AND the declared state (attribute, editing).
    def state_payload(attribute:, editing:)
      { "gid" => todo.to_gid.to_s, "s" => { "attribute" => attribute.to_s, "editing" => editing } }
    end

    it "restores the signed state so the mode survives an action" do
      # We are in edit mode (editing: true was signed by the prior render). The
      # endpoint must rebuild WITH editing: true — not the initialize default.
      post_action(InlineEditComponent,
        payload: state_payload(attribute: :title, editing: true),
        act: "cancel")

      expect(response).to have_http_status(:ok)
      # cancel flips editing -> false, so the response renders display mode.
      expect(response.body).to include('data-testid="display"')
    end

    it "save writes the SIGNED attribute, not a nil/blank column" do
      post_action(InlineEditComponent,
        payload: state_payload(attribute: :title, editing: true),
        act: "save",
        params: { value: "renamed" })

      expect(response).to have_http_status(:ok)
      expect(todo.reload.title).to eq("renamed") # the correct column, not nil
      expect(response.body).to include("renamed")
    end

    it "edit flips into edit mode and re-renders the input" do
      post_action(InlineEditComponent,
        payload: state_payload(attribute: :title, editing: false),
        act: "edit")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="field"')
      expect(response.body).to include('value="original"') # the signed attribute's value
    end

    it "rejects a token whose signed attribute was tampered" do
      token = token_for(InlineEditComponent, state_payload(attribute: :title, editing: true))
      # Re-encode the payload to switch the editable column onto the original
      # signature — verification must fail (the digest no longer matches).
      data, sig = token.split("--", 2)
      decoded = JSON.parse(Base64.urlsafe_decode64(data))
      decoded["_rails"]["data"]["s"]["attribute"] = "done"
      forged = "#{Base64.urlsafe_encode64(decoded.to_json, padding: false)}--#{sig}"

      post "/reactive/actions",
        params: { token: forged, act: "save", params: { value: "x" } }.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a token from a NEWER version than the running code (#111 — fails closed to 400)" do
      # A rolled-back deploy verifies a token minted by newer code (v ahead of
      # TOKEN_VERSION). verify returns nil, and the endpoint's existing
      # `|| raise(InvalidToken)` turns that into a 400 — no controller change.
      future = Phlex::Reactive.verifier.generate(
        { "c" => "TodoItemComponent", "gid" => "x", "v" => Phlex::Reactive::TOKEN_VERSION + 1 },
        purpose: Phlex::Reactive::IDENTITY_PURPOSE
      )

      post "/reactive/actions",
        params: { token: future, act: "toggle" }.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "blank field reaches the action; the component guards (issue #8)" do
    # The transport doesn't second-guess values: a genuinely-cleared field is
    # sent as "" and reaches the action. Protecting the record from a blank
    # write is the action's job (`if title.present?`), not the transport's. The
    # issue #8 fix is about COLLECTING the right value from rich-text/custom
    # editors in the first place — covered by spec/system/rich_editor_spec.rb.
    let!(:todo) { Todo.create!(title: "keep me", done: false) }

    it "passes an explicitly blank param through to the guarded action" do
      post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "rename", params: { title: "" })

      expect(response).to have_http_status(:ok)
      expect(todo.reload.title).to eq("keep me") # unchanged: guarded by `if title.present?`
    end
  end

  # Action response control: an action MAY return a Phlex::Reactive::Response to
  # govern the actor's HTTP reply (flash / remove / redirect / multi-stream).
  # Returning anything else keeps the legacy implicit single replace — proven by
  # the back-compat specs above (increment/toggle never return a Response).
  describe "Phlex::Reactive::Response control" do
    let!(:todo) { Todo.create!(title: "moderate me", done: false) }

    it "replace + flash: re-renders self (token refresh) AND appends a flash" do
      post_action(CounterComponent, payload: { "s" => { "count" => 5 } }, act: "reset_with_flash")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"')
      expect(response.body).to include('target="counter"') # self replace -> token refresh
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="flash"')
      expect(response.body).to include("Reset")
    end

    it "replace + flash: contains exactly ONE self-target stream (no double-prepend)" do
      post_action(CounterComponent, payload: { "s" => { "count" => 5 } }, act: "reset_with_flash")
      expect(response.body.scan('target="counter"').size).to eq(1)
    end

    # Regression: an update(self) response refreshes the signed token. The
    # endpoint guard keys off data-reactive-token-value (the invariant the client
    # reads), NOT "some stream targets self" — so it must NOT prepend a second,
    # contradictory replace when the update already carries a fresh token.
    it "update: morphs self with a fresh token and is NOT doubled with a replace" do
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "bump_via_update")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="update"')
      expect(response.body).to include('target="counter"')
      expect(response.body).to include("data-reactive-token-value=") # token refreshed
      expect(response.body).not_to include('action="replace"')       # no contradictory double-render
      expect(response.body).to match(/>\s*2\s*</) # 1 -> 2
    end

    # Issue #28: Response.morph(self) re-renders the element via Idiomorph
    # (action="replace" method="morph"). The morphed root carries a fresh token,
    # so the endpoint must NOT prepend a second, contradictory plain replace.
    it "morph: re-renders self with method=\"morph\" + a fresh token, not doubled" do
      post_action(CounterComponent, payload: { "s" => { "count" => 1 } }, act: "bump_via_morph")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="replace"')
      expect(response.body).to include('method="morph"')
      expect(response.body).to include('target="counter"')
      expect(response.body).to include("data-reactive-token-value=")    # token refreshed
      expect(response.body.scan('target="counter"').size).to eq(1)      # not doubled
      expect(response.body).to match(/>\s*2\s*</)                       # 1 -> 2
    end

    it "remove: emits a remove stream for the element and NO self replace" do
      post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "archive")

      dom = ActionView::RecordIdentifier.dom_id(todo)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(action="remove"))
      expect(response.body).to include(%(target="#{dom}"))
      expect(response.body).not_to include('action="replace"')
    end

    it "redirect: 200 turbo-stream carrying reactive:visit (NOT an HTTP 3xx)" do
      post_action(CounterComponent, payload: { "s" => { "count" => 0 } }, act: "go_home")

      expect(response).to have_http_status(:ok)
      expect(response).not_to be_redirect
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="reactive:visit"')
      expect(response.body).to include('data-url="/todos"')
    end

    it "flash-on-error keeps the row's token (self replace + flash both present)" do
      post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "rename_strict", params: { title: "" })

      dom = ActionView::RecordIdentifier.dom_id(todo)
      expect(response.body).to include(%(target="#{dom}")) # fresh token
      expect(response.body).to include('target="flash"')
      expect(todo.reload.title).to eq("moderate me") # unchanged on the error path
    end

    it "valid rename_strict updates and single-replaces" do
      post_action(TodoItemComponent, payload: { "gid" => todo.to_gid.to_s }, act: "rename_strict",
        params: { title: "renamed" })

      expect(response).to have_http_status(:ok)
      expect(todo.reload.title).to eq("renamed")
      expect(response.body).not_to include('target="flash"')
    end

    # Issue #30: reply.streams emits exactly the caller's streams and refreshes
    # the token via a tiny reactive:token stream — NOT a full-self replace — so a
    # partial/per-field update never tears down the component's live inputs.
    describe "streams (issue #30 — partial update + token-only refresh)" do
      it "emits the caller's stream AND a token-only refresh, with NO full-self replace" do
        post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_via_partial")

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        # The caller's own partial update is present...
        expect(response.body).to include('target="counter-mirror"')
        # ...the token is refreshed via the inert custom action...
        expect(response.body).to include('action="reactive:token"')
        expect(response.body).to include('target="counter"')
        expect(response.body).to include("data-reactive-token-value=") # the client extracts this
        # ...and the component is NOT fully re-rendered (no replace would clobber inputs).
        expect(response.body).not_to include('action="replace"')
      end

      it "does not re-render the component body (count is absent — inputs untouched)" do
        post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_via_partial")

        # The token-refresh stream carries no rendered children, so the next
        # count (5) appears only inside the caller's own mirror update, never as
        # a re-rendered <span> from a forced self replace.
        expect(response.body.scan('target="counter"').size).to eq(1) # only the token stream targets self
      end

      # Issue #180 automatic token refresh: reply.with — a companion-only reply
      # that does NOT re-render the root and binds no token_component. The
      # endpoint must append a token-only stream automatically (NOT a full-self
      # replace that could clobber inputs), so reply.with and reply.streams
      # converge — the author no longer picks a verb to keep the token fresh.
      it "auto-refreshes the token for a reply.with that doesn't re-render the root" do
        post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_via_with")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('target="counter-mirror"') # the caller's stream
        expect(response.body).to include('action="reactive:token"') # auto token refresh
        expect(response.body).to include('target="counter"')
        expect(response.body).to include("data-reactive-token-value=")
        expect(response.body).not_to include('action="replace"') # NOT a full-self replace
      end

      it "does not double the token when a reply.with already re-renders the root" do
        # bump_via_with_self returns reply.with(self.class.replace(...)) — the
        # raw self-replace string already carries the fresh token, so the
        # auto-refresh must stay idempotent (no extra reactive:token, one target).
        post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_via_with_self")

        expect(response.body).not_to include('action="reactive:token"')
        expect(response.body.scan('target="counter"').size).to eq(1)
      end

      # Regression: the dedupe must be scoped to the ACTOR's target, not a global
      # substring. A partial reply that includes ANOTHER component's stream (which
      # legitimately carries its own data-reactive-token-value) must STILL refresh
      # this component's token — otherwise the actor's next action 400s.
      it "still refreshes the actor's token when a SIBLING component's stream carries one" do
        post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_with_sibling")

        # Capture the sibling the ACTION created (not a preexisting fixture), so
        # the sibling-target assertions actually exercise the action's output.
        sibling = Todo.find_by!(title: "sibling")
        sibling_dom = ActionView::RecordIdentifier.dom_id(sibling)

        expect(response).to have_http_status(:ok)
        # The sibling's replace (carrying ITS own token) is present and targets
        # the sibling — this is the "another component's token" the dedupe must
        # NOT mistake for the actor's.
        expect(response.body).to include('action="replace"')
        expect(response.body).to include(%(target="#{sibling_dom}"))
        # ...AND the actor's own token-only refresh is still appended, targeting self.
        expect(response.body).to include('action="reactive:token"')
        expect(response.body).to include('target="counter"')
        # The actor's token stream is the ONLY thing targeting the counter (no self replace).
        expect(response.body.scan('target="counter"').size).to eq(1)
        # Sanity: the sibling stream targets the sibling, not the counter.
        expect(sibling_dom).not_to eq("counter")
      end

      # Idempotency (the flip side of the issue #44 fix): when the caller's own
      # streams ALREADY include a self-replace/update (which re-renders the root
      # and carries the fresh token), the endpoint must NOT also append a token-only
      # stream — that would double the token. carries_token_for? counts a
      # self-RENDERING stream (replace/update at the actor's target), so exactly one
      # token-bearing stream targets self.
      it "does NOT double the token when the caller's streams already re-render self" do
        post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_with_self_stream")

        expect(response).to have_http_status(:ok)
        # The caller's self-replace is present (re-renders the root, carries the token)...
        expect(response.body).to include('action="replace"')
        expect(response.body).to include('target="counter"')
        # ...and it is NOT doubled with an extra reactive:token stream.
        expect(response.body).not_to include('action="reactive:token"')
        # Exactly one stream targets self — the caller's self-replace, no extra.
        expect(response.body.scan('target="counter"').size).to eq(1)
        expect(response.body.scan("data-reactive-token-value=").size).to eq(1)
      end
    end

    # Issue #97: reply.<verb>.js(ops) pushes server-side client DOM ops over a
    # reactive:js stream. The op stream must ride AFTER the render stream (so a
    # focus op sees the post-render DOM — Turbo applies streams in document
    # order) and must NOT count as a self-render (its action name is reactive:js,
    # not replace/update/reactive:token), so the morph's own token refresh is
    # untouched.
    describe "js (issue #97 — server-pushed client DOM ops)" do
      it "emits the reactive:js op stream AFTER the render stream" do
        post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_with_js")

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")

        render_at = response.body.index('action="replace"')
        js_at = response.body.index('action="reactive:js"')
        expect(render_at).not_to be_nil
        expect(js_at).not_to be_nil
        expect(js_at).to be > render_at # ops LAST — focus sees the morphed DOM
      end

      it "keeps the morph's token refresh intact (reactive:js is not a self-render)" do
        post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_with_js")

        # The morph carries the fresh token; the endpoint must NOT append an extra
        # reactive:token, and the reactive:js stream must NOT suppress the refresh.
        expect(response.body).to include("data-reactive-token-value=")
        expect(response.body).not_to include('action="reactive:token"')
        # The morph re-renders self (carries the token); the js stream targets self
        # too, but only the morph is a token-bearing self-render.
        expect(response.body.scan("data-reactive-token-value=").size).to eq(1)
      end

      it "carries the ops HTML-escaped (no attribute break-out)" do
        post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_with_js")

        expect(response.body).to include("data-reactive-ops=")
        expect(response.body).to include("&quot;focus&quot;")
        expect(response.body).to include("&quot;app:bumped&quot;")
      end

      it "scopes the op stream to the component's own id (self-scoped @root)" do
        post_action(CounterComponent, payload: { "s" => { "count" => 4 } }, act: "bump_with_js")

        expect(response.body).to include('<turbo-stream action="reactive:js" target="counter"')
      end
    end
  end

  describe "tampering" do
    it "rejects a forged token" do
      post "/reactive/actions",
        params: { token: "not.a.real.token", act: "increment" }.to_json,
        headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:bad_request)
    end
  end
end
