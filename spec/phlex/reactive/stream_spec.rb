# frozen_string_literal: true

require "rails_helper"

# Issue #114: Phlex::Reactive::Stream is a structured value object that IS an
# html_safe String (so it drops into `render turbo_stream:`, ERB/Phlex
# interpolation, and Turbo test-helper substring asserts unchanged) but ALSO
# carries the structural facts the endpoint needs — action / target /
# renders_root — plus a token flag computed ONCE from GROUND TRUTH (the html
# bytes), never inferred from the builder kind. It replaces the endpoint's
# regex-sniffing of its own generated turbo-stream markup with structural reads.
RSpec.describe Phlex::Reactive::Stream do
  # A minimal html_safe replace stream that carries the token attribute.
  def replace_html(target: "counter", token: "TOK")
    inner = %(<div id="#{target}" data-reactive-token-value="#{token}">x</div>)
    %(<turbo-stream action="replace" target="#{target}"><template>#{inner}</template></turbo-stream>).html_safe
  end

  # A minimal append stream whose CHILD carries its own token, at the container
  # target — the issue #44 shape.
  def append_html(target: "list", token: "ROWTOK")
    inner = %(<li id="row_1" data-reactive-token-value="#{token}">row</li>)
    %(<turbo-stream action="append" target="#{target}"><template>#{inner}</template></turbo-stream>).html_safe
  end

  describe ".wrap — structural attributes" do
    subject(:stream) do
      described_class.wrap(replace_html, action: "replace", target: "counter", renders_root: true)
    end

    it "carries action, target, renders_root set structurally at construction" do
      expect(stream.rx_action).to eq("replace")
      expect(stream.rx_target).to eq("counter")
      expect(stream.rx_renders_root?).to be(true)
    end

    it "coerces action/target to strings and renders_root to a boolean" do
      s = described_class.wrap(replace_html, action: :replace, target: :counter, renders_root: "yes")
      expect(s.rx_action).to eq("replace")
      expect(s.rx_target).to eq("counter")
      expect(s.rx_renders_root?).to be(true)
    end
  end

  describe "#rx_carries_token? — GROUND TRUTH, never inferred from action" do
    it "is true when the html actually contains the token attribute" do
      s = described_class.wrap(replace_html, action: "replace", target: "counter", renders_root: true)
      expect(s.rx_carries_token?).to be(true)
    end

    # The load-bearing cosmos#1939 guard: a stream whose ACTION is a self-render
    # (replace) but whose HTML omits the token must answer false — otherwise the
    # endpoint would skip the fallback token refresh and reintroduce the
    # add-once-only bug class.
    it "is false when the action is replace but the html omits the token attribute" do
      inner = %(<div id="counter">no token here</div>)
      html = %(<turbo-stream action="replace" target="counter"><template>#{inner}</template></turbo-stream>).html_safe
      s = described_class.wrap(html, action: "replace", target: "counter", renders_root: true)
      expect(s.rx_carries_token?).to be(false)
    end

    it "is true for an append whose CHILD embeds a token (ground truth reads the bytes)" do
      s = described_class.wrap(append_html, action: "append", target: "list", renders_root: false)
      expect(s.rx_carries_token?).to be(true)
    end
  end

  describe "IS-A html_safe String (mandatory public-API interop)" do
    subject(:stream) do
      described_class.wrap(replace_html, action: "replace", target: "counter", renders_root: true)
    end

    it "is an ActiveSupport::SafeBuffer and reports html_safe?" do
      expect(stream).to be_a(ActiveSupport::SafeBuffer)
      expect(stream.html_safe?).to be(true)
    end

    it "responds to to_str (implicit String conversion for String#<<)" do
      expect(stream).to respond_to(:to_str)
      expect(stream.to_str).to eq(replace_html)
    end

    it "is byte-identical to the wrapped html (no escaping, byte-identical wire)" do
      expect(stream.to_s).to eq(replace_html.to_s)
      expect(String.new(stream)).to eq(replace_html.to_s)
    end

    it "substring-asserts like a String (Turbo test-helper interop)" do
      expect(stream).to include('action="replace"')
      expect(stream).to include('target="counter"')
      expect(stream).to include("data-reactive-token-value")
    end

    it "interpolates into another string, degrading to a plain (safe) String" do
      combined = "PREFIX#{stream}"
      expect(combined).to include("PREFIX")
      expect(combined).to include('action="replace"')
    end
  end

  describe "immutability + metadata-loss story (spec #114 item 4)" do
    subject(:stream) do
      described_class.wrap(replace_html, action: "replace", target: "counter", renders_root: true)
    end

    it "is frozen (an immutable value object)" do
      expect(stream).to be_frozen
    end

    # dup KEEPS the class + ivars (only unfreezes). It therefore takes the
    # STRUCTURAL path with ACCURATE fields — the bytes are identical. (Do NOT
    # expect a dup to degrade to the legacy path; it does not.)
    it "dup keeps the class and the structural attributes" do
      d = stream.dup
      expect(d).to be_a(described_class)
      expect(d.rx_action).to eq("replace")
      expect(d.rx_target).to eq("counter")
      expect(d.rx_carries_token?).to be(true)
    end

    # gsub reshapes the bytes and returns a plain String — is_a?(Stream) is
    # false, so the endpoint treats it as an opaque raw string (legacy path).
    it "gsub returns a plain String that has lost the Stream metadata" do
      g = stream.gsub("replace", "update")
      expect(g).not_to be_a(described_class)
      expect(g).not_to respond_to(:rx_action)
    end
  end

  describe "#rx_refreshes_token_for? — structural token dedupe (replaces the regex)" do
    it "is true for a token-bearing self-replace at the component's own target" do
      s = described_class.wrap(replace_html(target: "counter"), action: "replace", target: "counter", renders_root: true)
      expect(s.rx_refreshes_token_for?("counter")).to be(true)
    end

    # Issue #30: a SIBLING component's replace targets a DIFFERENT id, so it must
    # NOT count as the actor's own token refresh.
    it "is false for a replace targeting a DIFFERENT id (sibling — issue #30)" do
      s = described_class.wrap(replace_html(target: "other"), action: "replace", target: "other", renders_root: true)
      expect(s.rx_refreshes_token_for?("counter")).to be(false)
    end

    # Issue #44: an appended reactive ROW carries its OWN token at the container
    # target, but renders_root is false — it inserts a CHILD, it does not
    # re-render the container's root — so it must NEVER count as the container's
    # own token refresh.
    it "is false for an append even when the child row embeds a token (issue #44)" do
      s = described_class.wrap(append_html(target: "list"), action: "append", target: "list", renders_root: false)
      expect(s.rx_carries_token?).to be(true) # the child's token IS in the bytes...
      expect(s.rx_refreshes_token_for?("list")).to be(false) # ...but renders_root false ⇒ no refresh
    end

    it "is false for a remove stream (renders_root false, no token)" do
      html = %(<turbo-stream action="remove" target="counter"></turbo-stream>).html_safe
      s = described_class.wrap(html, action: "remove", target: "counter", renders_root: false)
      expect(s.rx_refreshes_token_for?("counter")).to be(false)
    end

    it "is a self-render for the inert reactive:token stream" do
      html = %(<turbo-stream action="reactive:token" target="counter" ) +
             %(data-reactive-token-value="TOK"></turbo-stream>)
      s = described_class.wrap(html.html_safe, action: "reactive:token", target: "counter", renders_root: true)
      expect(s.rx_refreshes_token_for?("counter")).to be(true)
    end
  end
end
