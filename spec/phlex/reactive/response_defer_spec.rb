# frozen_string_literal: true

require "rails_helper"

# Response#defer / reply.defer (issue #165): record a deferred segment — a
# component whose render is taken OFF the actor's critical path. The Response
# only RECORDS the segment (component + placeholder + morph); building the
# directive/placeholder streams, minting the token, and picking the lane happen
# at the ENDPOINT after the action's transaction committed (Defer module), so a
# rolled-back action can never leak a directive.
RSpec.describe "Phlex::Reactive::Response#defer" do
  let(:counter) { CounterComponent.new(count: 0) }
  let(:totals) { CounterComponent.new(count: 42) }

  describe "recording segments" do
    it "returns a NEW frozen Response carrying the segment (immutable chain)" do
      base = Phlex::Reactive::Response.replace(counter)
      deferred = base.defer(totals)

      expect(deferred).not_to equal(base)
      expect(deferred).to be_frozen
      expect(base.deferred_segments).to be_empty # original untouched
      expect(deferred.deferred_segments.size).to eq(1)
      expect(deferred.deferred_segments.first.component).to equal(totals)
    end

    it "defaults to keep-content (no placeholder) and a plain replace arrival" do
      segment = Phlex::Reactive::Response.replace(counter).defer(totals).deferred_segments.first
      expect(segment.placeholder).to be_nil
      expect(segment.morph).to be(false)
    end

    it "records placeholder: and morph:" do
      segment = Phlex::Reactive::Response.replace(counter)
        .defer(totals, placeholder: "<p>loading</p>", morph: true)
        .deferred_segments.first

      expect(segment.placeholder).to eq("<p>loading</p>")
      expect(segment.morph).to be(true)
    end

    it "stacks multiple segments in order" do
      other = CounterComponent.new(count: 7)
      response = Phlex::Reactive::Response.replace(counter).defer(totals).defer(other)

      expect(response.deferred_segments.map(&:component)).to eq([totals, other])
    end

    it "deferred? reflects the presence of segments" do
      # Fresh instances per Response.replace — a Phlex component renders once.
      expect(Phlex::Reactive::Response.replace(CounterComponent.new(count: 0)).deferred?).to be(false)
      expect(Phlex::Reactive::Response.replace(CounterComponent.new(count: 0)).defer(totals).deferred?).to be(true)
    end
  end

  describe "chain preservation" do
    it "survives .flash / .stream / .also_update chained AFTER defer" do
      response = Phlex::Reactive::Response.replace(counter)
        .defer(totals)
        .flash(:notice, "saved")
        .also_update("heading", html: "Hi")

      expect(response.deferred_segments.size).to eq(1)
      expect(response.streams.size).to eq(3) # replace + flash + also_update
    end

    it "preserves token_component / render_self through the defer chain" do
      response = Phlex::Reactive::Response.streams(counter, "<turbo-stream></turbo-stream>").defer(totals)

      expect(response.render_self?).to be(false)
      expect(response.token_component).to equal(counter)
    end
  end

  describe "loud failures at the call site" do
    it "rejects defer on a redirect reply (the client is navigating away)" do
      expect { Phlex::Reactive::Response.redirect("/x").defer(totals) }
        .to raise_error(Phlex::Reactive::Error, /redirect/)
    end

    it "rejects a component that is not a reactive component (cannot be rebuilt from identity)" do
      plain = Class.new(Phlex::HTML) do
        def self.name = "PlainThing"
        def view_template = div { "x" }
      end

      expect { Phlex::Reactive::Response.replace(counter).defer(plain.new) }
        .to raise_error(ArgumentError, /Phlex::Reactive::Component/)
    end

    it "rejects a placeholder that is neither nil, true, a String, nor a Phlex component" do
      expect { Phlex::Reactive::Response.replace(counter).defer(totals, placeholder: 42) }
        .to raise_error(ArgumentError, /placeholder/)
    end
  end

  describe "reply.defer (the bound facade)" do
    # Review finding (#165): reply.defer with no prior verb must NOT keep
    # render_self — that made GUARD 2 inject a full synchronous to_stream_replace
    # of the acting component, so deferring silently paid the render on the
    # critical path anyway (a double-render when the deferred segment IS self).
    # The bound component's token is refreshed via a tiny token-only stream
    # instead (like reply.streams), so it rolls forward with NO full self-render.
    it "reply.defer alone refreshes the token WITHOUT a full self-render (no double render)" do
      response = counter.reply.defer(totals)

      expect(response).to be_a(Phlex::Reactive::Response)
      expect(response.render_self?).to be(false)
      expect(response.token_component).to equal(counter)
      expect(response.deferred_segments.first.component).to equal(totals)
    end

    it "chains off reply verbs: reply.streams(...).defer(...) — the #165 shape" do
      response = counter.reply.streams("<turbo-stream></turbo-stream>").defer(totals)

      expect(response.render_self?).to be(false)
      expect(response.token_component).to equal(counter)
      expect(response.deferred_segments.size).to eq(1)
    end

    it "accepts placeholder:/morph: passthrough" do
      response = counter.reply.defer(totals, placeholder: true, morph: true)
      segment = response.deferred_segments.first

      expect(segment.placeholder).to be(true)
      expect(segment.morph).to be(true)
    end
  end
end
