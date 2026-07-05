# frozen_string_literal: true

require "rails_helper"

# The defer transport gates (issue #165). Two layers, per the pgbus-optionality
# invariant (capability-detect at runtime, never defined?(Pgbus) alone or a
# version string):
#
#   * pgbus?          — pgbus is loaded and exposes the Streams entrypoint
#   * pgbus_streams?  — the reactive Streams capability probe: the stream's
#                       broadcast accepts :exclude (pgbus >= 0.9.2 shape)
#   * defer_push_capable? — everything the push lane needs: pgbus_streams? +
#                       SignedName.sign (server-side src minting) + ActiveJob
#
# The default suite runs WITHOUT pgbus loaded (require: false — no Postgres),
# so the absent path is the real default here; the present paths use doubles.
RSpec.describe "Phlex::Reactive defer capability gates" do
  after do
    Phlex::Reactive.defer_transport = nil
  end

  describe ".pgbus?" do
    it "is false when ::Pgbus is not loaded (the default suite)" do
      skip "pgbus is loaded in this process" if defined?(Pgbus)
      expect(Phlex::Reactive.pgbus?).to be(false)
    end

    it "is false when ::Pgbus exists but has no .stream (pre-Streams pgbus)" do
      stub_const("Pgbus", Module.new)
      expect(Phlex::Reactive.pgbus?).to be(false)
    end

    it "is true when ::Pgbus.stream exists" do
      stub_const("Pgbus", Module.new do
        def self.stream(*) = nil
      end)
      expect(Phlex::Reactive.pgbus?).to be(true)
    end
  end

  describe ".pgbus_streams?" do
    it "is false without pgbus" do
      skip "pgbus is loaded in this process" if defined?(Pgbus)
      expect(Phlex::Reactive.pgbus_streams?).to be(false)
    end

    it "is false for an old-shape Stream whose broadcast lacks :exclude" do
      old_stream = Class.new do
        def broadcast(payload, target: nil) = [payload, target]
      end
      pgbus = Module.new { def self.stream(*) = nil }
      stub_const("Pgbus", pgbus)
      stub_const("Pgbus::Streams", Module.new)
      stub_const("Pgbus::Streams::Stream", old_stream)

      expect(Phlex::Reactive.pgbus_streams?).to be(false)
    end

    it "is true when the broadcast accepts :exclude (the capability, not a version)" do
      new_stream = Class.new do
        def broadcast(payload, visible_to: nil, durable: nil, exclude: nil, event: nil,
                      coalesce: nil, target: nil)
          [payload, visible_to, durable, exclude, event, coalesce, target]
        end
      end
      pgbus = Module.new { def self.stream(*) = nil }
      stub_const("Pgbus", pgbus)
      stub_const("Pgbus::Streams", Module.new)
      stub_const("Pgbus::Streams::Stream", new_stream)

      expect(Phlex::Reactive.pgbus_streams?).to be(true)
    end
  end

  describe ".defer_push_capable?" do
    let(:capable_stream) do
      Class.new do
        def broadcast(payload, visible_to: nil, durable: nil, exclude: nil, event: nil,
                      coalesce: nil, target: nil)
          [payload, visible_to, durable, exclude, event, coalesce, target]
        end
      end
    end

    it "is false without pgbus (pull is the only lane)" do
      skip "pgbus is loaded in this process" if defined?(Pgbus)
      expect(Phlex::Reactive.defer_push_capable?).to be(false)
    end

    it "is true with streams-capable pgbus + SignedName + ActiveJob" do
      pgbus = Module.new { def self.stream(*) = nil }
      stub_const("Pgbus", pgbus)
      stub_const("Pgbus::Streams", Module.new)
      stub_const("Pgbus::Streams::Stream", capable_stream)
      stub_const("Pgbus::Streams::SignedName", Module.new do
        def self.sign(name) = "signed-#{name}"
      end)

      # ActiveJob is a dev/test dependency and loaded by the dummy app.
      expect(defined?(ActiveJob::Base)).to be_truthy
      expect(Phlex::Reactive.defer_push_capable?).to be(true)
    end

    it "is false when SignedName is missing (cannot mint a src server-side)" do
      pgbus = Module.new { def self.stream(*) = nil }
      stub_const("Pgbus", pgbus)
      stub_const("Pgbus::Streams", Module.new)
      stub_const("Pgbus::Streams::Stream", capable_stream)

      expect(Phlex::Reactive.defer_push_capable?).to be(false)
    end
  end

  describe ".defer_transport" do
    it "defaults to :auto" do
      expect(Phlex::Reactive.defer_transport).to eq(:auto)
    end

    it "accepts :fetch and :stream, and a String form" do
      Phlex::Reactive.defer_transport = :fetch
      expect(Phlex::Reactive.defer_transport).to eq(:fetch)
      Phlex::Reactive.defer_transport = "stream"
      expect(Phlex::Reactive.defer_transport).to eq(:stream)
    end

    it "rejects an unknown transport loudly at assignment" do
      expect { Phlex::Reactive.defer_transport = :carrier_pigeon }
        .to raise_error(ArgumentError, /defer_transport/)
    end

    it "resets to the default via nil" do
      Phlex::Reactive.defer_transport = :fetch
      Phlex::Reactive.defer_transport = nil
      expect(Phlex::Reactive.defer_transport).to eq(:auto)
    end
  end

  describe ".defer_path" do
    it "defaults to /reactive/defer" do
      expect(Phlex::Reactive.defer_path).to eq("/reactive/defer")
    end
  end
end
