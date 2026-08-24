# frozen_string_literal: true

require "rails_helper"

# Issue #232: the request-derived url_options thread-local that makes URL
# helpers correct in ACTOR replies. The endpoint sets it for the duration of a
# reactive request; the memoized off-request view context merges it over its
# process defaults; the broadcast render clears it (subscribers can be on
# different hosts).
RSpec.describe "Phlex::Reactive url_options threading (issue #232)" do
  describe ".with_url_options / .current_url_options" do
    it "defaults to nil (off-request renders keep process defaults)" do
      expect(Phlex::Reactive.current_url_options).to be_nil
    end

    it "exposes the options inside the block and restores the previous value after" do
      Phlex::Reactive.with_url_options({ host: "yoga.test" }) do
        expect(Phlex::Reactive.current_url_options).to eq({ host: "yoga.test" })
      end
      expect(Phlex::Reactive.current_url_options).to be_nil
    end

    it "restores on raise" do
      expect do
        Phlex::Reactive.with_url_options({ host: "yoga.test" }) { raise "boom" }
      end.to raise_error("boom")
      expect(Phlex::Reactive.current_url_options).to be_nil
    end

    it "nests — nil CLEARS the actor options for an inner render (the broadcast guard)" do
      Phlex::Reactive.with_url_options({ host: "yoga.test" }) do
        Phlex::Reactive.with_url_options(nil) do
          expect(Phlex::Reactive.current_url_options).to be_nil
        end
        expect(Phlex::Reactive.current_url_options).to eq({ host: "yoga.test" })
      end
    end
  end

  describe ".url_options_for(request)" do
    def request_for(url)
      ActionDispatch::Request.new(Rack::MockRequest.env_for(url))
    end

    it "extracts protocol, host, and explicit port" do
      options = Phlex::Reactive.url_options_for(request_for("http://yoga.local:1120/x"))
      expect(options).to eq({ protocol: "http://", host: "yoga.local", port: 1120 })
    end

    it "extracts a nil port on the default port (so a stale configured port is cleared)" do
      options = Phlex::Reactive.url_options_for(request_for("https://yoga.test/x"))
      expect(options).to eq({ protocol: "https://", host: "yoga.test", port: nil })
    end
  end

  describe "the memoized off-request view context" do
    after { Phlex::Reactive.reset_stream_builder! }

    it "merges the actor options over its process defaults, without rebuilding" do
      context = Phlex::Reactive.off_request_view_context
      default_url = context.url_for(controller: "demos", action: "counter", only_path: false)

      Phlex::Reactive.with_url_options({ protocol: "http://", host: "yoga.test", port: 1120 }) do
        expect(Phlex::Reactive.off_request_view_context).to be(context)
        expect(context.url_for(controller: "demos", action: "counter", only_path: false))
          .to eq("http://yoga.test:1120/counter")
      end

      # Cleared afterwards — the same memoized context is back on defaults.
      expect(context.url_for(controller: "demos", action: "counter", only_path: false)).to eq(default_url)
    end
  end
end
