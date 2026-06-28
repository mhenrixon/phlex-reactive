# frozen_string_literal: true

require "rails_helper"

# End-to-end (through the action endpoint) coverage of the reactive_collection
# helper (issue #35): an action calls reply.append/reply.remove on a declared
# collection, and the endpoint renders the row + count + empty-state streams.
RSpec.describe "Reactive collection endpoint (issue #35)", type: :request do
  def token_for(klass, payload = {})
    Phlex::Reactive.sign(payload.merge("c" => klass.name))
  end

  def post_action(klass, act:, params: {}, payload: {})
    post "/reactive/actions",
      params: {token: token_for(klass, payload), act:, params:}.to_json,
      headers: {"Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html"}
  end

  let(:klass) { NotificationsListComponent }

  describe "add (reply.append)" do
    it "creates the record and appends the row into the container" do
      expect {
        post_action(klass, act: "add", params: {title: "ping"})
      }.to change(Todo, :count).by(1)

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
      post_action(klass, act: "add", params: {title: "second"})

      expect(response.body).to include('target="notifications-count"')
      # 1 existing + 1 added = 2
      expect(response.body).to match(/target="notifications-count".*>\s*2\s*</m)
    end

    it "removes the empty-state when the first row crosses 0->1" do
      expect(Todo.count).to eq(0)
      post_action(klass, act: "add", params: {title: "first"})

      expect(response.body).to include('action="remove"')
      expect(response.body).to include('target="notifications-empty"')
    end

    it "leaves the empty-state alone when the list was already populated" do
      Todo.create!(title: "existing")
      post_action(klass, act: "add", params: {title: "another"})

      expect(response.body).not_to include('target="notifications-empty"')
    end

    it "does not re-render the whole container (render_self false — only the delta)" do
      Todo.create!(title: "existing")
      post_action(klass, act: "add", params: {title: "new"})

      # The container's own root id is never replaced — only the row appended.
      expect(response.body).not_to include('target="notifications-list"')
    end
  end

  describe "dismiss (reply.remove)" do
    let!(:todo) { Todo.create!(title: "dismiss me") }

    it "destroys the record and removes the row by its dom id" do
      dom_id = ActionView::RecordIdentifier.dom_id(todo)
      expect {
        post_action(klass, act: "dismiss", params: {id: todo.id})
      }.to change(Todo, :count).by(-1)

      expect(response.body).to include('action="remove"')
      expect(response.body).to include(%(target="#{dom_id}"))
    end

    it "updates the count companion" do
      Todo.create!(title: "other")
      post_action(klass, act: "dismiss", params: {id: todo.id})

      # 2 existing - 1 dismissed = 1
      expect(response.body).to match(/target="notifications-count".*>\s*1\s*</m)
    end

    it "restores the empty-state when the last row is dismissed (->0)" do
      post_action(klass, act: "dismiss", params: {id: todo.id})

      expect(Todo.count).to eq(0)
      expect(response.body).to include("No notifications")
      expect(response.body).to match(/action="append".*target="notifications"/m)
    end

    it "leaves the empty-state out while rows remain" do
      Todo.create!(title: "survivor")
      post_action(klass, act: "dismiss", params: {id: todo.id})

      expect(response.body).not_to include("No notifications")
    end
  end

  describe "default-deny still holds" do
    it "forbids an undeclared action on the collection container" do
      post_action(klass, act: "drop_everything")
      expect(response).to have_http_status(:forbidden)
    end
  end
end
