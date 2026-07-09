# frozen_string_literal: true

require "rails_helper"

# Issue #215: the PER-CALL effect override. `effect:` on a stream builder /
# reply verb stamps data-reactive-effect on the <turbo-stream> element itself
# — the client resolves it FIRST (it beats the root-declared attrs; "off"
# suppresses). No kwarg = byte-identical wire (the attr never appears).
RSpec.describe Phlex::Reactive::Effects, "per-call effect: (streams + reply)" do
  let(:todo) { Todo.create!(title: "t", done: false) }

  # The attr must ride the OPENING <turbo-stream> tag, never the template body.
  def opening_tag(stream)
    stream.to_s[0..stream.to_s.index(">")]
  end

  describe "class builders" do
    it "stamps replace" do
      stream = TodoItemComponent.replace(todo, effect: :fade)
      expect(opening_tag(stream)).to include('data-reactive-effect="fade"')
    end

    it "stamps update" do
      stream = TodoItemComponent.update(todo, effect: :highlight)
      expect(opening_tag(stream)).to include('data-reactive-effect="highlight"')
    end

    it "stamps append and prepend" do
      expect(opening_tag(TodoItemComponent.append(target: "list", model: todo, effect: :slide)))
        .to include('data-reactive-effect="slide"')
      expect(opening_tag(TodoItemComponent.prepend(target: "list", model: todo, effect: :scale)))
        .to include('data-reactive-effect="scale"')
    end

    it "stamps remove" do
      stream = TodoItemComponent.remove(todo, effect: :shake)
      expect(opening_tag(stream)).to include('data-reactive-effect="shake"')
    end

    it "omits the attr entirely without the kwarg (byte-identical wire)" do
      expect(TodoItemComponent.replace(todo)).not_to include("data-reactive-effect")
      expect(TodoItemComponent.remove(todo)).not_to include("data-reactive-effect")
    end

    it "serializes effect: false as \"off\" (suppress a root-declared effect)" do
      stream = TodoItemComponent.remove(todo, effect: false)
      expect(opening_tag(stream)).to include('data-reactive-effect="off"')
    end

    it "escapes legs JSON into the attribute" do
      stream = TodoItemComponent.remove(todo, effect: { during: "d", from: "f", to: "t" })
      expect(opening_tag(stream))
        .to include('data-reactive-effect="[&quot;d&quot;,&quot;f&quot;,&quot;t&quot;]"')
    end

    it "rejects an unknown effect name at the call site" do
      expect { TodoItemComponent.replace(todo, effect: :sparkle) }
        .to raise_error(ArgumentError, /sparkle/)
    end

    it "combines with morph: (both attributes present)" do
      stream = TodoItemComponent.replace(todo, morph: true, effect: :highlight)
      expect(opening_tag(stream)).to include('method="morph"')
      expect(opening_tag(stream)).to include('data-reactive-effect="highlight"')
    end

    it "keeps the structural Stream metadata (the endpoint reads fields, not markup)" do
      stream = TodoItemComponent.replace(todo, effect: :fade)
      expect(stream).to be_a(Phlex::Reactive::Stream)
      expect(stream.rx_action).to eq("replace")
      expect(stream.rx_target).to eq(ActionView::RecordIdentifier.dom_id(todo))
      expect(stream.rx_renders_root?).to be(true)
      expect(stream.rx_carries_token?).to be(true)
    end
  end

  describe "instance primitives" do
    it "stamps to_stream_replace / to_stream_update / to_stream_remove" do
      expect(opening_tag(CounterComponent.new(count: 0).to_stream_replace(effect: :fade)))
        .to include('data-reactive-effect="fade"')
      expect(opening_tag(CounterComponent.new(count: 0).to_stream_update(effect: :fade)))
        .to include('data-reactive-effect="fade"')
      expect(opening_tag(CounterComponent.new(count: 0).to_stream_remove(effect: :fade)))
        .to include('data-reactive-effect="fade"')
    end

    it "stays byte-identical without the kwarg" do
      expect(CounterComponent.new(count: 0).to_stream_replace).not_to include("data-reactive-effect")
    end
  end

  describe "reply verbs" do
    let(:counter) { CounterComponent.new(count: 0) }

    it "threads effect: through replace / morph / update / remove" do
      expect(counter.reply.replace(effect: :fade).streams.first)
        .to include('data-reactive-effect="fade"')
      expect(CounterComponent.new(count: 0).reply.morph(effect: :highlight).streams.first)
        .to include('data-reactive-effect="highlight"')
      expect(CounterComponent.new(count: 0).reply.update(effect: :fade).streams.first)
        .to include('data-reactive-effect="fade"')
      expect(CounterComponent.new(count: 0).reply.remove(effect: :shake).streams.first)
        .to include('data-reactive-effect="shake"')
    end

    it "reply.morph keeps method=\"morph\" alongside the effect attr" do
      stream = counter.reply.morph(effect: :highlight).streams.first
      expect(stream).to include('method="morph"')
      expect(stream).to include('data-reactive-effect="highlight"')
    end
  end

  describe "reply collection verbs" do
    let(:row_component) do
      Class.new(ApplicationComponent) do
        include Phlex::Reactive::Streamable

        def self.name = "FxCollRow"
        def self.model_param_name = :todo
        def initialize(todo:) = @todo = todo
        def id = dom_id(@todo)
        def view_template = li(id:) { @todo.title }
      end
    end

    let(:container_class) do
      row = row_component
      Class.new(ApplicationComponent) do
        include Phlex::Reactive::Streamable
        include Phlex::Reactive::Component

        def self.name = "FxCollList"

        reactive_collection :todos, item: row, container: "fx-list", count: "fx-count", size: -> { @size }

        def initialize(size: 1) = @size = size
        def id = "fx-list-root"
        def view_template = div(id:, **reactive_attrs) { "" }
      end
    end

    it "stamps the ROW stream on append, leaving the count companion plain" do
      response = container_class.new.reply.append(todo, to: :todos, effect: :slide)
      row_stream, count_stream = response.streams
      expect(opening_tag(row_stream)).to include('data-reactive-effect="slide"')
      expect(count_stream).not_to include("data-reactive-effect")
    end

    it "stamps the ROW stream on remove" do
      response = container_class.new.reply.remove(todo, from: :todos, effect: :fade)
      expect(opening_tag(response.streams.first)).to include('data-reactive-effect="fade"')
    end

    it "stays byte-identical without the kwarg" do
      response = container_class.new.reply.append(todo, to: :todos)
      expect(response.streams.join).not_to include("data-reactive-effect")
    end
  end
end
