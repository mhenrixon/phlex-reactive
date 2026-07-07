# frozen_string_literal: true

require "rails_helper"

# The collection stream builders (issue #35): reply.append/prepend/remove(name,
# model) resolve the bound container's reactive_collection declaration and emit
# the row stream + the count companion update + the empty-state toggle as ONE
# Response — so a list stays correct without per-action append/count/empty
# bookkeeping. These render through the configured renderer, so rails_helper.
RSpec.describe "reactive_collection streams (issue #35)", type: :request do
  # A row component keyed off a Todo (so dom_id works for append/remove targets).
  let(:row_component) do
    Class.new(ApplicationComponent) do
      include Phlex::Reactive::Streamable

      def self.name = "CollSpecRow"
      def self.model_param_name = :todo
      def initialize(todo:) = @todo = todo
      def id = dom_id(@todo)
      def view_template = li(id:) { @todo.title }
    end
  end

  # An empty-state component with a stable id (toggled in/out at the 0<->1 edge).
  let(:empty_component) do
    Class.new(ApplicationComponent) do
      include Phlex::Reactive::Streamable

      def self.name = "CollSpecEmpty"
      def id = "todos-empty"
      def view_template = div(id:) { "No todos yet" }
    end
  end

  # The container declares the collection. size: reads a stubbed count so we can
  # drive the 0<->1 boundary without touching the DB count.
  let(:container_class) do
    row = row_component
    empty = empty_component
    Class.new(ApplicationComponent) do
      include Phlex::Reactive::Streamable
      include Phlex::Reactive::Component

      def self.name = "CollSpecList"

      reactive_collection :todos,
        item: row,
        container: "todos-list",
        count: "todos-count",
        empty: empty,
        size: -> { @size }

      def initialize(size: 0) = @size = size
      def id = "todos-list-root"
      def view_template = div(id:, **reactive_attrs) { "" }
    end
  end

  let(:todo) { Todo.create!(title: "buy milk", done: false) }
  let(:dom_id) { ActionView::RecordIdentifier.dom_id(todo) }

  describe "reply.append(model, to:)" do
    it "appends the row component into the container" do
      response = container_class.new(size: 1).reply.append(todo, to: :todos)
      append = response.streams.find { it.include?('action="append"') }
      expect(append).to include('target="todos-list"')
      expect(append).to include(%(id="#{dom_id}"))
      expect(append).to include("buy milk")
    end

    it "updates the count companion with the fresh size" do
      response = container_class.new(size: 1).reply.append(todo, to: :todos)
      count = response.streams.find { it.include?('target="todos-count"') }
      expect(count).to include('action="update"')
      expect(count).to include(">1<").or include("1")
    end

    it "removes the empty-state when the list crosses 0->1 (size becomes 1)" do
      response = container_class.new(size: 1).reply.append(todo, to: :todos)
      empty = response.streams.find { it.include?('target="todos-empty"') }
      expect(empty).to include('action="remove"')
    end

    it "does NOT touch the empty-state when the list was already non-empty (size > 1)" do
      response = container_class.new(size: 2).reply.append(todo, to: :todos)
      expect(response.streams).not_to include(a_string_including('target="todos-empty"'))
    end

    it "opts to render_self false (the row append is the update, not a self replace)" do
      response = container_class.new(size: 1).reply.append(todo, to: :todos)
      expect(response.render_self?).to be(false)
    end

    # cosmos#1939: render_self false MUST still refresh the container's token, or
    # the list is add-once-only. The Response binds the container as token_component
    # so the endpoint appends its inert reactive:token stream (the #30 machinery).
    it "binds the container as token_component so its token rolls forward" do
      container = container_class.new(size: 1)
      response = container.reply.append(todo, to: :todos)
      expect(response.refresh_token?).to be(true)
      expect(response.token_component).to eq(container)
    end
  end

  describe "reply.prepend(model, to:)" do
    it "prepends the row into the container and still updates count" do
      response = container_class.new(size: 1).reply.prepend(todo, to: :todos)
      expect(response.streams).to include(a_string_including('action="prepend"', 'target="todos-list"'))
      expect(response.streams).to include(a_string_including('target="todos-count"'))
    end

    it "binds the container as token_component (cosmos#1939)" do
      container = container_class.new(size: 1)
      expect(container.reply.prepend(todo, to: :todos).token_component).to eq(container)
    end
  end

  describe "reply.remove(model, from:)" do
    it "removes the row by its dom id" do
      response = container_class.new(size: 0).reply.remove(todo, from: :todos)
      remove = response.streams.find { it.include?(%(target="#{dom_id}")) }
      expect(remove).to include('action="remove"')
    end

    it "updates the count companion with the fresh size" do
      response = container_class.new(size: 0).reply.remove(todo, from: :todos)
      expect(response.streams).to include(a_string_including('target="todos-count"', 'action="update"'))
    end

    it "restores the empty-state when the list crosses ->0 (size becomes 0)" do
      response = container_class.new(size: 0).reply.remove(todo, from: :todos)
      empty = response.streams.find { it.include?('target="todos-list"') && it.include?("No todos yet") }
      expect(empty).to include('action="append"')
    end

    it "does NOT restore the empty-state while rows remain (size > 0)" do
      response = container_class.new(size: 3).reply.remove(todo, from: :todos)
      expect(response.streams).not_to include(a_string_including("No todos yet"))
    end

    it "binds the container as token_component so repeated removes work (cosmos#1939)" do
      container = container_class.new(size: 0)
      response = container.reply.remove(todo, from: :todos)
      expect(response.refresh_token?).to be(true)
      expect(response.token_component).to eq(container)
    end

    it "accepts a dom-id string as well as a model" do
      response = container_class.new(size: 0).reply.remove(dom_id, from: :todos)
      remove = response.streams.find { it.include?('action="remove"') }
      expect(remove).to include(%(target="#{dom_id}"))
    end
  end

  describe "optional declarations" do
    let(:minimal_container) do
      row = row_component
      Class.new(ApplicationComponent) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "MinimalCollList"
        reactive_collection :todos, item: row, container: "todos-list"
        def id = "min-root"
        def view_template = div(id:) { "" }
      end
    end

    it "emits only the row stream when count/empty/size are not declared" do
      response = minimal_container.new.reply.append(todo, to: :todos)
      expect(response.streams.size).to eq(1)
      expect(response.streams.first).to include('action="append"')
    end
  end

  describe "chaining" do
    it "the returned Response chains .flash like any other reply" do
      response = container_class.new(size: 1).reply.append(todo, to: :todos).flash(:notice, "added")
      expect(response.streams.last).to include('action="append"')
      expect(response.streams.last).to include("added")
    end

    it "the returned Response is frozen" do
      expect(container_class.new(size: 1).reply.append(todo, to: :todos)).to be_frozen
    end
  end

  # Issue #186: reply.append/prepend thread extra kwargs to the row component's
  # new(model:, **kwargs) — the class API + broadcast_append_to already do this;
  # Response.collection_* was the only caller forwarding nothing.
  describe "row kwargs (issue #186)" do
    let(:kw_row) do
      Class.new(ApplicationComponent) do
        include Phlex::Reactive::Streamable

        def self.name = "KwRow"
        def self.model_param_name = :todo

        def initialize(todo:, autofocus: false)
          @todo = todo
          @autofocus = autofocus
        end

        def id = dom_id(@todo)
        def view_template = li(id:, autofocus: @autofocus) { @todo.title }
      end
    end

    let(:kw_container) do
      row = kw_row
      Class.new(ApplicationComponent) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "KwList"
        reactive_collection :todos, item: row, container: "todos-list"
        def initialize(size: 0) = @size = size
        def id = "kw-list-root"
        def view_template = div(id:, **reactive_attrs) { "" }
      end
    end

    it "threads a row kwarg to the row component (append)" do
      response = kw_container.new.reply.append(todo, to: :todos, autofocus: true)
      expect(response.streams.first.to_s).to include("autofocus")
    end

    it "threads a row kwarg to the row component (prepend)" do
      response = kw_container.new.reply.prepend(todo, to: :todos, autofocus: true)
      expect(response.streams.first.to_s).to include("autofocus")
    end

    it "is additive — a no-kwarg append still works" do
      response = kw_container.new.reply.append(todo, to: :todos)
      expect(response.streams.first.to_s).not_to include("autofocus")
    end
  end

  describe "errors" do
    it "raises a clear error for an undeclared collection" do
      expect { container_class.new.reply.append(todo, to: :nope) }
        .to raise_error(Phlex::Reactive::Error, /undeclared reactive_collection :nope/)
    end

    it "raises a guided ArgumentError for the removed Symbol-first form" do
      expect { container_class.new.reply.append(:nope, todo) }
        .to raise_error(ArgumentError, /to:/)
    end
  end
end
