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

  it "flash accepts a Phlex component, rendered through the configured renderer" do
    klass = Class.new(Phlex::HTML) do
      def self.name = "FlashAlertProbe" # ActionView's render logger needs a name
      def view_template = span { "rendered flash" }
    end
    response = described_class.with.flash(:error, klass.new)
    expect(response.streams.first).to include("rendered flash")
  end
end
