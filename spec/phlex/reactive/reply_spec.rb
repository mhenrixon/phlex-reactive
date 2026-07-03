# frozen_string_literal: true

require "rails_helper"

# Component#reply returns a subject-bound facade over Response, so an action body
# writes `reply.replace.flash(:error, msg)` instead of
# `Phlex::Reactive::Response.replace(self).flash(:error, msg)` — no constant to
# qualify (it's a method, resolved on the component) and no `self` to thread.
#
# Reply is sugar: every verb returns the SAME frozen Response the endpoint reads,
# so these specs lock parity with Response.* on the observable surface (streams,
# redirect?, render_self?) rather than via == (Response has no value equality).
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

  describe "verbs return a real Response with the same surface as Response.*" do
    it "replace mirrors Response.replace(self)" do
      via_reply = counter.reply.replace
      via_class = Phlex::Reactive::Response.replace(CounterComponent.new(count: 0))

      expect(via_reply).to be_a(Phlex::Reactive::Response)
      expect(via_reply.render_self?).to eq(via_class.render_self?)
      expect(via_reply.streams.first).to include('action="replace"')
      expect(via_reply.streams.first).not_to include("method=") # plain swap by default
    end

    it "replace(morph: true) mirrors Response.replace(self, morph: true)" do
      stream = counter.reply.replace(morph: true).streams.first
      expect(stream).to include('action="replace"')
      expect(stream).to include('method="morph"')
    end

    it "morph mirrors Response.morph(self)" do
      stream = counter.reply.morph.streams.first
      expect(stream).to include('action="replace"')
      expect(stream).to include('method="morph"')
    end

    it "update mirrors Response.update(self)" do
      stream = counter.reply.update.streams.first
      expect(stream).to include('action="update"')
      expect(stream).not_to include("method=") # plain update by default
    end

    it "update(morph: true) mirrors Response.update(self, morph: true) — issue #113" do
      stream = counter.reply.update(morph: true).streams.first
      expect(stream).to include('action="update"')
      expect(stream).to include('method="morph"')
    end

    it "remove mirrors Response.remove(self) — render_self false" do
      response = item.reply.remove
      expect(response.render_self?).to be(false)
      expect(response.streams.first).to include('action="remove"')
      expect(response.streams.first).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "redirect mirrors Response.redirect(url) — render_self false, carries url" do
      response = counter.reply.redirect("/x")
      expect(response.redirect?).to be(true)
      expect(response.redirect_url).to eq("/x")
      expect(response.render_self?).to be(false)
    end

    it "with mirrors Response.with(*streams)" do
      response = counter.reply.with("<turbo-stream></turbo-stream>")
      expect(response).to be_a(Phlex::Reactive::Response)
      expect(response.streams).to eq(["<turbo-stream></turbo-stream>"])
    end

    # Issue #30: reply.streams(*) is the bound form of Response.streams(self, *) —
    # emit exactly these streams, refresh the token via a tiny stream (NOT a full
    # self replace), so per-field/partial updates don't clobber live inputs.
    it "streams mirrors Response.streams(self, *streams) — render_self false, component bound" do
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

    it "reply.replace.also_update appends a companion stream" do
      response = counter.reply.replace.also_update("page_heading", html: "New")
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
