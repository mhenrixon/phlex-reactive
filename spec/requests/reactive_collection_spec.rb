# frozen_string_literal: true

require "rails_helper"

# End-to-end (through the action endpoint) coverage of the reactive_collection
# helper (issue #35): an action calls reply.append/reply.remove on a declared
# collection, and the endpoint renders the row + count + empty-state streams.
RSpec.describe "Reactive collection endpoint (issue #35)", type: :request do
  let(:klass) { NotificationsListComponent }

  describe "add (reply.append)" do
    it "creates the record and appends the row into the container" do
      expect do
        post_action(klass, act: "add", params: { title: "ping" })
      end.to change(Todo, :count).by(1)

      expect(response).to have_http_status(:ok)
      todo = Todo.order(:id).last
      dom_id = ActionView::RecordIdentifier.dom_id(todo)
      expect(response.body).to include('action="append"')
      expect(response.body).to include('target="notifications"')
      expect(response.body).to include(%(id="#{dom_id}"))
      expect(response.body).to include("ping")
    end

    it "updates the count companion with the new size" do
      Todo.create!(title: "existing")
      post_action(klass, act: "add", params: { title: "second" })

      expect(response.body).to include('target="notifications-count"')
      # 1 existing + 1 added = 2
      expect(response.body).to match(/target="notifications-count".*>\s*2\s*</m)
    end

    it "removes the empty-state when the first row crosses 0->1" do
      expect(Todo.count).to eq(0)
      post_action(klass, act: "add", params: { title: "first" })

      expect(response.body).to include('action="remove"')
      expect(response.body).to include('target="notifications-empty"')
    end

    it "leaves the empty-state alone when the list was already populated" do
      Todo.create!(title: "existing")
      post_action(klass, act: "add", params: { title: "another" })

      expect(response.body).not_to include('target="notifications-empty"')
    end

    it "does not re-render the whole container body (render_self false — only the delta)" do
      Todo.create!(title: "existing")
      post_action(klass, act: "add", params: { title: "new" })

      # The container's body is never re-rendered — no replace/update of its root.
      # (The container IS targeted by the inert reactive:token refresh, which only
      # rolls the token forward without touching the children — that's expected.)
      expect(response.body).not_to include('action="replace" target="notifications-list"')
      expect(response.body).not_to include('action="update" target="notifications-list"')
    end
  end

  describe "dismiss (reply.remove)" do
    let!(:todo) { Todo.create!(title: "dismiss me") }

    it "destroys the record and removes the row by its dom id" do
      dom_id = ActionView::RecordIdentifier.dom_id(todo)
      expect do
        post_action(klass, act: "dismiss", params: { id: todo.id })
      end.to change(Todo, :count).by(-1)

      expect(response.body).to include('action="remove"')
      expect(response.body).to include(%(target="#{dom_id}"))
    end

    it "updates the count companion" do
      Todo.create!(title: "other")
      post_action(klass, act: "dismiss", params: { id: todo.id })

      # 2 existing - 1 dismissed = 1
      expect(response.body).to match(/target="notifications-count".*>\s*1\s*</m)
    end

    it "restores the empty-state when the last row is dismissed (->0)" do
      post_action(klass, act: "dismiss", params: { id: todo.id })

      expect(Todo.count).to eq(0)
      expect(response.body).to include("No notifications")
      expect(response.body).to match(/action="append".*target="notifications"/m)
    end

    it "leaves the empty-state out while rows remain" do
      Todo.create!(title: "survivor")
      post_action(klass, act: "dismiss", params: { id: todo.id })

      expect(response.body).not_to include("No notifications")
    end
  end

  describe "default-deny still holds" do
    it "forbids an undeclared action on the collection container" do
      post_action(klass, act: "drop_everything")
      expect(response).to have_http_status(:forbidden)
    end
  end

  # Regression for cosmos#1939 (and the generalized #30 lesson): a reply that does
  # NOT re-render self must STILL refresh self's token. reply.append/remove opt out
  # of the full-self replace (render_self false), so without a token refresh on the
  # CONTAINER (which owns the add/remove trigger) the list's signed token goes
  # stale after the first action and every subsequent dispatch is rejected — an
  # add-once-only list, broken with no error. The helper must emit the inert
  # reactive:token stream for the container on every add/remove.
  describe "token refresh on the collection container (cosmos#1939)" do
    # The container's #id ("notifications-list") is the reactive:token target.
    let(:container_id) { "notifications-list" }

    it "append emits a reactive:token stream targeting the container" do
      post_action(klass, act: "add", params: { title: "ping" })

      expect(response.body).to include('action="reactive:token"')
      expect(response.body).to include(%(target="#{container_id}"))
    end

    it "remove emits a reactive:token stream targeting the container" do
      todo = Todo.create!(title: "bye")
      post_action(klass, act: "dismiss", params: { id: todo.id })

      expect(response.body).to include('action="reactive:token"')
      expect(response.body).to include(%(target="#{container_id}"))
    end

    # The load-bearing assertion: dispatch a SECOND add using the token the FIRST
    # response rolled forward, and it must succeed. A stale-token helper 400s here.
    it "supports repeated adds — the second uses the token the first refreshed" do
      post_action(klass, act: "add", params: { title: "first" })
      expect(response).to have_http_status(:ok)
      next_token = token_from(response.body, container_id)
      expect(next_token).to be_present

      post "/reactive/actions",
        params: { token: next_token, act: "add", params: { title: "second" } }.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(Todo.count).to eq(2)
      expect(response.body).to include("second")
    end

    it "supports an add then a remove using the chained refreshed tokens" do
      post_action(klass, act: "add", params: { title: "row" })
      todo = Todo.order(:id).last
      token_after_add = token_from(response.body, container_id)

      post "/reactive/actions",
        params: { token: token_after_add, act: "dismiss", params: { id: todo.id } }.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(Todo.count).to eq(0)
    end
  end

  # Regression for issue #44: when the container's #id EQUALS the append target
  # AND the rows are themselves reactive (each carries its OWN
  # data-reactive-token-value), the row's embedded token landed in the SAME stream
  # string as `target="<container>"`. carries_token_for? matched
  # `include?("data-reactive-token-value") && include?(target)` in that one string
  # → both true → it concluded the container's token was already fresh and SKIPPED
  # the container's reactive:token refresh. So the container's token never rolled
  # forward and the second add was rejected — collections of reactive rows were
  # add-once-only. The fix: a stream "carries the token for C" only when its action
  # RE-RENDERS C itself (replace/update/reactive:token at C's target); append/prepend
  # (which insert children INTO C) must never count.
  describe "container id == append target with reactive rows (issue #44)" do
    let(:klass) { ReactiveRowsListComponent }
    let(:container_id) { "reactive-rows" }

    it "still emits the container's reactive:token even though the prepended row carries its own token" do
      post_action(klass, act: "add", params: { title: "ping" })

      expect(response).to have_http_status(:ok)
      # The appended row IS reactive — it carries its own token, at the container target.
      expect(response.body).to include('action="append"')
      expect(response.body).to include(%(target="#{container_id}"))
      # ...and the container's OWN token-only refresh is STILL present (this is what
      # carries_token_for? wrongly suppressed before the fix).
      expect(response.body).to include('action="reactive:token"')
      expect(token_from(response.body, container_id)).to be_present
    end

    # The load-bearing assertion: a SECOND add using the token the first response
    # rolled forward must succeed. Before the fix this 400s (stale container token).
    it "supports repeated adds — the second uses the token the first refreshed" do
      post_action(klass, act: "add", params: { title: "first" })
      expect(response).to have_http_status(:ok)
      next_token = token_from(response.body, container_id)
      expect(next_token).to be_present

      post "/reactive/actions",
        params: { token: next_token, act: "add", params: { title: "second" } }.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(Todo.count).to eq(2)
      expect(response.body).to include("second")
    end
  end

  # Pull the fresh data-reactive-token-value from the reactive:token stream that
  # targets the given container id — exactly what the client's #extractToken does.
  def token_from(body, container_id)
    stream = body[/<turbo-stream action="reactive:token" target="#{Regexp.escape(container_id)}"[^>]*>/]
    stream && stream[/data-reactive-token-value="([^"]+)"/, 1]
  end
end
