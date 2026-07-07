# frozen_string_literal: true

require "rails_helper"

# Component#reply returns a subject-bound facade that builds the Response value
# object the endpoint reads, so an action body writes `reply.replace.flash(:error,
# msg)` — no constant to qualify (it's a method, resolved on the component) and no
# `self` to thread. Issue #182 made reply the ONLY door (the Response.* class
# verbs are removed), so the builder logic lives on Response as private-by-name
# `build_*` class methods that Reply calls.
#
# Reply is the ONE door (issue #182): every verb returns a frozen Response the
# endpoint reads. These specs lock the observable surface (streams, redirect?,
# render_self?) directly — the former Response.* class verbs are removed, so
# there is nothing to mirror against, only the behavior to assert.
RSpec.describe Phlex::Reactive::Reply do
  let(:counter) { CounterComponent.new(count: 0) }
  let(:todo) { Todo.create!(title: "t", done: false) }
  let(:item) { TodoItemComponent.new(todo:) }

  describe "Component#reply" do
    it "returns a Reply bound to the component" do
      expect(counter.reply).to be_a(described_class)
    end

    it "resolves inside a namespaced component with no Response constant in scope" do
      # The whole point: reply is method dispatch on self, not lexical constant
      # lookup — so a namespaced component needs no `Response =` alias.
      namespaced = Class.new(ApplicationComponent) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "Deeply::Nested::Widget"

        reactive_state :n
        action :noop
        def initialize(n: 0) = @n = n
        def id = "widget"
        # bare `reply`, no constant
        def noop = reply.replace
        def view_template = div(id:, **reactive_attrs) { @n.to_s }
      end

      expect { namespaced.new.noop }.not_to raise_error
      expect(namespaced.new.noop).to be_a(Phlex::Reactive::Response)
    end
  end

  describe "verbs return a real Response with the expected surface" do
    it "replace re-renders self in place (render_self, plain swap)" do
      via_reply = counter.reply.replace

      expect(via_reply).to be_a(Phlex::Reactive::Response)
      expect(via_reply.render_self?).to be(true)
      expect(via_reply.streams.first).to include('action="replace"')
      expect(via_reply.streams.first).not_to include("method=") # plain swap by default
    end

    it "replace(morph: true) emits a morph swap" do
      stream = counter.reply.replace(morph: true).streams.first
      expect(stream).to include('action="replace"')
      expect(stream).to include('method="morph"')
    end

    it "morph emits a morph swap" do
      stream = counter.reply.morph.streams.first
      expect(stream).to include('action="replace"')
      expect(stream).to include('method="morph"')
    end

    it "update emits a plain update stream" do
      stream = counter.reply.update.streams.first
      expect(stream).to include('action="update"')
      expect(stream).not_to include("method=") # plain update by default
    end

    it "update(morph: true) emits a morph update — issue #113" do
      stream = counter.reply.update(morph: true).streams.first
      expect(stream).to include('action="update"')
      expect(stream).to include('method="morph"')
    end

    it "remove drops self, render_self false" do
      response = item.reply.remove
      expect(response.render_self?).to be(false)
      expect(response.streams.first).to include('action="remove"')
      expect(response.streams.first).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "redirect carries the url, render_self false" do
      response = counter.reply.redirect("/x")
      expect(response.redirect?).to be(true)
      expect(response.redirect_url).to eq("/x")
      expect(response.render_self?).to be(false)
    end

    it "with emits raw streams verbatim" do
      response = counter.reply.with("<turbo-stream></turbo-stream>")
      expect(response).to be_a(Phlex::Reactive::Response)
      expect(response.streams).to eq(["<turbo-stream></turbo-stream>"])
    end

    # Issue #30: reply.streams(*) is the bound form of Response.streams(self, *) —
    # emit exactly these streams, refresh the token via a tiny stream (NOT a full
    # self replace), so per-field/partial updates don't clobber live inputs.
    it "streams emits partial streams, render_self false, component bound" do
      response = counter.reply.streams(item.to_stream_update)
      expect(response).to be_a(Phlex::Reactive::Response)
      expect(response.render_self?).to be(false)
      expect(response.token_component).to eq(counter)
      expect(response.streams.first).to include('action="update"')
    end
  end

  describe "chaining works on the returned Response (immutability preserved)" do
    it "reply.replace.flash composes two streams" do
      response = counter.reply.replace.flash(:notice, "hi")
      expect(response.streams.size).to eq(2)
      expect(response.streams.last).to include('action="append"')
      expect(response.streams.last).to include("hi")
    end

    it "reply.replace.also appends a companion stream" do
      response = counter.reply.replace.also(page_heading: "New")
      expect(response.streams.size).to eq(2)
      expect(response.streams.last).to include('target="page_heading"')
    end

    it "reply.morph.flash chains a flash onto a morph" do
      response = counter.reply.morph.flash(:notice, "saved")
      expect(response.streams.first).to include('method="morph"')
      expect(response.streams.last).to include('action="append"')
    end

    it "the returned Response is frozen" do
      expect(counter.reply.replace).to be_frozen
    end
  end
end
