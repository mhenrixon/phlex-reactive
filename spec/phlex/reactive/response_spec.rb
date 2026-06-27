# frozen_string_literal: true

require "rails_helper"

# The Response value object is unit-testable as a plain return value — no
# controller/request boot. (to_stream_* and flash_builder render through the
# configured renderer, so rails_helper provides the view context.)
RSpec.describe Phlex::Reactive::Response do
  let(:counter) { CounterComponent.new(count: 0) }
  let(:todo) { Todo.create!(title: "t", done: false) }
  let(:item) { TodoItemComponent.new(todo:) }

  it "replace renders a self-targeted replace stream and keeps render_self" do
    response = described_class.replace(counter)
    expect(response.render_self?).to be(true)
    expect(response.redirect?).to be(false)
    expect(response.streams.size).to eq(1)
    expect(response.streams.first).to include('action="replace"')
    expect(response.streams.first).to include('target="counter"')
  end

  it "replace + flash composes two streams" do
    response = described_class.replace(counter).flash(:notice, "hi")
    expect(response.streams.size).to eq(2)
    expect(response.streams.last).to include('action="append"')
    expect(response.streams.last).to include('target="flash"')
    expect(response.streams.last).to include("hi")
  end

  it "remove opts out of render_self and emits a remove stream" do
    response = described_class.remove(item)
    expect(response.render_self?).to be(false)
    expect(response.streams.first).to include('action="remove"')
    expect(response.streams.first).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
  end

  it "redirect carries the url, opts out of render_self, and has no streams" do
    response = described_class.redirect("/x")
    expect(response.redirect?).to be(true)
    expect(response.redirect_url).to eq("/x")
    expect(response.render_self?).to be(false)
    expect(response.streams).to be_empty
  end

  it "is immutable — stream/flash return new instances" do
    base = described_class.replace(counter)
    expect(base.stream("<turbo-stream></turbo-stream>")).not_to equal(base)
    expect(base.streams.size).to eq(1) # original unchanged
    expect(base).to be_frozen
  end

  # Issue #25: re-render self + a companion element/component without dropping to
  # raw turbo_stream_builder.
  describe "also_update / also_replace (companion elements)" do
    it "also_update appends an update stream for an arbitrary target id" do
      response = described_class.replace(counter).also_update("page_heading", html: "New name")

      expect(response.streams.size).to eq(2)
      expect(response.render_self?).to be(true)
      expect(response.streams.last).to include('action="update"')
      expect(response.streams.last).to include('target="page_heading"')
      expect(response.streams.last).to include("New name")
    end

    it "also_update HTML-escapes a plain string but renders a Phlex component" do
      probe = Class.new(Phlex::HTML) do
        def self.name = "HeadingProbe"
        def view_template = strong { "Bold heading" }
      end
      response = described_class.with.also_update("page_heading", html: probe.new)

      expect(response.streams.first).to include("<strong>Bold heading</strong>")
    end

    it "also_replace renders another Streamable component, targeting its own id" do
      response = described_class.replace(counter).also_replace(item)

      expect(response.streams.size).to eq(2)
      expect(response.streams.last).to include('action="replace"')
      expect(response.streams.last).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "is immutable — also_* return new instances and keep render_self" do
      base = described_class.replace(counter)
      extended = base.also_update("h", html: "x")
      expect(extended).not_to equal(base)
      expect(base.streams.size).to eq(1) # original unchanged
      expect(extended.render_self?).to be(true)
    end

    it "chains alongside flash and stream" do
      response = described_class.replace(counter)
        .also_update("heading", html: "n")
        .flash(:notice, "saved")

      expect(response.streams.size).to eq(3)
    end
  end

  it "flash accepts a Phlex component, rendered through the configured renderer" do
    klass = Class.new(Phlex::HTML) do
      def self.name = "FlashAlertProbe" # ActionView's render logger needs a name
      def view_template = span { "rendered flash" }
    end
    response = described_class.with.flash(:error, klass.new)
    expect(response.streams.first).to include("rendered flash")
  end
end
