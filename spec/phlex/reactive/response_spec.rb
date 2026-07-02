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

    it "also_update renders a Phlex component (auto-escaped) into the companion stream" do
      probe = Class.new(Phlex::HTML) do
        def self.name = "HeadingProbe"
        def view_template = strong { "Bold heading" }
      end
      response = described_class.with.also_update("page_heading", html: probe.new)

      expect(response.streams.first).to include("<strong>Bold heading</strong>")
    end

    it "also_update HTML-escapes a plain string (a model value is safe)" do
      # Turbo's TagBuilder escapes a plain String passed to html:, so a model
      # value can't inject markup. (Pass an html_safe string or a Phlex
      # component to emit intentional raw HTML.)
      response = described_class.with.also_update("page_heading", html: "<em>Live</em>")

      expect(response.streams.first).to include("&lt;em&gt;Live&lt;/em&gt;")
      expect(response.streams.first).not_to include("<em>Live</em>")
    end

    it "also_update emits an html_safe string as raw markup" do
      response = described_class.with.also_update("page_heading", html: "<em>Live</em>".html_safe)

      expect(response.streams.first).to include("<em>Live</em>")
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

  # Issue #28: morph re-renders self in place via Idiomorph (method="morph"),
  # preserving the focused input + caret. Response.morph(self) is the explicit
  # builder; Response.replace(self, morph: true) is the opt-in flag; also_replace
  # gains a morph: flag for companion components.
  describe "morph (issue #28)" do
    it "morph renders a self-targeted morphing replace and keeps render_self" do
      response = described_class.morph(counter)
      expect(response.render_self?).to be(true)
      expect(response.redirect?).to be(false)
      expect(response.streams.size).to eq(1)
      expect(response.streams.first).to include('action="replace"')
      expect(response.streams.first).to include('method="morph"')
      expect(response.streams.first).to include('target="counter"')
    end

    it "replace(morph: true) emits the morph attribute" do
      response = described_class.replace(counter, morph: true)
      expect(response.streams.first).to include('method="morph"')
    end

    it "replace defaults to a plain swap (no morph attr) — back-compat" do
      response = described_class.replace(counter)
      expect(response.streams.first).not_to include("method=")
    end

    it "morph composes with flash (token still refreshes via the morph)" do
      response = described_class.morph(counter).flash(:notice, "saved")
      expect(response.streams.size).to eq(2)
      expect(response.streams.first).to include('method="morph"')
      expect(response.streams.last).to include('action="append"')
    end

    it "also_replace(component, morph: true) morphs the companion component" do
      response = described_class.morph(counter).also_replace(item, morph: true)
      expect(response.streams.size).to eq(2)
      expect(response.streams.last).to include('method="morph"')
      expect(response.streams.last).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "also_replace defaults to a plain replace (no morph attr)" do
      response = described_class.replace(counter).also_replace(item)
      expect(response.streams.last).not_to include("method=")
    end
  end

  # Issue #77: the flash level must reach the wire. String content gets a
  # level-carrying wrapper (class + data attribute); Phlex component content
  # renders VERBATIM (byte-identical to before — the caller owns the markup);
  # Phlex::Reactive.flash_component swaps the default wrapper for the app's own
  # flash component (string content only).
  describe "flash levels (issue #77)" do
    it ":error and :notice produce different streams" do
      error = described_class.with.flash(:error, "boom").streams.first
      notice = described_class.with.flash(:notice, "saved").streams.first

      expect(error.to_s.gsub("boom", "MSG")).not_to eq(notice.to_s.gsub("saved", "MSG"))
      expect(error).to include('class="reactive-flash reactive-flash--error"')
      expect(error).to include('data-reactive-flash-level="error"')
      expect(notice).to include('class="reactive-flash reactive-flash--notice"')
      expect(notice).to include('data-reactive-flash-level="notice"')
    end

    it "keeps HTML-escaping plain string content (injection contract unchanged)" do
      stream = described_class.with.flash(:notice, "<em>x</em> & y").streams.first

      expect(stream).to include("&lt;em&gt;x&lt;/em&gt; &amp; y")
      expect(stream).not_to include("<em>x</em>")
      expect(stream).to include('class="reactive-flash reactive-flash--notice"')
    end

    it "passes an html_safe string verbatim INSIDE the wrapper (intentional raw HTML)" do
      stream = described_class.with.flash(:notice, "<em>x</em>".html_safe).streams.first

      expect(stream).to include('data-reactive-flash-level="notice"')
      expect(stream).to include("<em>x</em>")
    end

    it "HTML-escapes the level (it lands in a class name and a data attribute)" do
      stream = described_class.with.flash(%(err"or><script>), "x").streams.first

      expect(stream).not_to include('err"or><script>')
      expect(stream).to include("err&quot;or&gt;&lt;script&gt;")
    end

    it "renders Phlex component content VERBATIM — byte-identical to the raw builder append, no wrapper" do
      klass = Class.new(Phlex::HTML) do
        def self.name = "FlashPassthroughProbe"
        def view_template = span { "rendered flash" }
      end

      via_flash = described_class.with.flash(:error, klass.new).streams.first
      raw = Phlex::Reactive.flash_builder.append("flash", html: Phlex::Reactive.render(klass.new))

      expect(via_flash.to_s).to eq(raw.to_s)
      expect(via_flash).not_to include("reactive-flash")
    end

    describe "Phlex::Reactive.flash_component" do
      let(:flash_component) do
        Class.new(Phlex::HTML) do
          def self.name = "AppFlashProbe"

          def initialize(level:, content:)
            @level = level
            @content = content
          end

          def view_template = div(class: "toast toast--#{@level}") { @content }
        end
      end

      around do
        Phlex::Reactive.flash_component = flash_component
        it.run
      ensure
        Phlex::Reactive.flash_component = nil
      end

      it "renders string content through the configured component (level + content)" do
        stream = described_class.with.flash(:error, "Save failed").streams.first

        expect(stream).to include('class="toast toast--error"')
        expect(stream).to include("Save failed")
        expect(stream).not_to include("reactive-flash")
      end

      it "component content still bypasses flash_component (renders verbatim)" do
        klass = Class.new(Phlex::HTML) do
          def self.name = "CustomFlashCard"
          def view_template = span { "custom card" }
        end

        stream = described_class.with.flash(:error, klass.new).streams.first

        expect(stream).to include("<span>custom card</span>")
        expect(stream).not_to include("toast")
      end
    end
  end

  it "flash accepts a Phlex component, rendered through the configured renderer" do
    klass = Class.new(Phlex::HTML) do
      # ActionView's render logger needs a name
      def self.name = "FlashAlertProbe"
      def view_template = span { "rendered flash" }
    end
    response = described_class.with.flash(:error, klass.new)
    expect(response.streams.first).to include("rendered flash")
  end

  # Issue #30: Response.streams(component, *strings) emits EXACTLY the caller's
  # streams plus a token-only refresh — render_self is false (no full-self
  # replace), so partial/per-field updates don't clobber live inputs, yet the
  # signed token still rolls forward via the tiny reactive:token stream the
  # endpoint appends from the bound component.
  describe "streams (issue #30 — partial update, token-only refresh)" do
    it "opts out of render_self (no forced full-self replace)" do
      response = described_class.streams(counter, "<turbo-stream></turbo-stream>")
      expect(response.render_self?).to be(false)
    end

    it "carries exactly the caller's streams (does not prepend a self replace)" do
      response = described_class.streams(counter, item.to_stream_update)
      expect(response.streams.size).to eq(1)
      expect(response.streams.first).to include('action="update"')
      expect(response.streams.first).to include(%(target="#{ActionView::RecordIdentifier.dom_id(todo)}"))
    end

    it "remembers the bound component so the endpoint can refresh its token" do
      response = described_class.streams(counter, "<turbo-stream></turbo-stream>")
      expect(response.token_component).to eq(counter)
    end

    it "is NOT redirect and is immutable" do
      response = described_class.streams(counter)
      expect(response.redirect?).to be(false)
      expect(response).to be_frozen
    end

    it "chains flash/stream while staying render_self false and keeping the component" do
      response = described_class.streams(counter, item.to_stream_update).flash(:notice, "saved")
      expect(response.streams.size).to eq(2)
      expect(response.streams.last).to include('action="append"')
      expect(response.render_self?).to be(false)
      expect(response.token_component).to eq(counter)
    end
  end
end
