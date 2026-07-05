# frozen_string_literal: true

require "rails_helper"

# DeferredRenderJob failure handling (issue #165 review finding, MAJOR): the
# job rescued ONLY RecordNotFound, so ANY other error (a render raising, a
# broadcast failing, from_identity raising a non-RecordNotFound) propagated
# with no cleanup broadcast — and the stream lane has no client-side timeout,
# so the actor's shimmer hangs forever. Every failure the job can recover from
# must broadcast the cleanup (pending-clear + source teardown) so the pending
# state resolves; only a broadcast that ITSELF fails is allowed to propagate
# (there's nothing we could deliver anyway).
RSpec.describe "Phlex::Reactive::DeferredRenderJob failure handling" do
  let(:stream_key) { "prdefer_0123456789abcdef0123456789abcdef" }
  let(:broadcasts) { [] }

  before do
    recorder = broadcasts
    stream = Object.new
    stream.define_singleton_method(:broadcast) { recorder << it }
    pgbus = Module.new
    pgbus.define_singleton_method(:stream) do |key, durable: nil|
      recorder << { key:, durable: }
      stream
    end
    stub_const("Pgbus", pgbus)
  end

  def perform(payload = { "c" => "SlowTotalsComponent", "s" => { "value" => 1 } }, klass: "SlowTotalsComponent")
    Phlex::Reactive::DeferredRenderJob.new.perform(klass, payload, stream_key, "slow-totals", false)
  end

  it "broadcasts the cleanup when the RENDER raises (not just RecordNotFound)" do
    allow_any_instance_of(SlowTotalsComponent).to receive(:to_stream_replace).and_raise(RuntimeError, "render boom")

    expect { perform }.not_to raise_error
    html = broadcasts.last
    expect(html).to include('action="reactive:js"') # pending-clear ops
    expect(html).to include('action="remove" target="reactive-defer-src-slow-totals"')
  end

  it "broadcasts the cleanup when from_identity raises a non-RecordNotFound error" do
    allow(SlowTotalsComponent).to receive(:from_identity).and_raise(RuntimeError, "identity boom")

    expect { perform }.not_to raise_error
    expect(broadcasts.last).to include('action="reactive:js"')
  end

  it "lets a cleanup-broadcast failure propagate (nothing deliverable — the job may retry)" do
    # If the render fails AND the cleanup broadcast itself fails, there's no
    # recovery path — the job must not swallow it (ActiveJob can retry). Every
    # broadcast on this stream raises, so the cleanup can't be delivered.
    failing = Object.new
    failing.define_singleton_method(:broadcast) { |_| raise("pg down") }
    pgbus = Module.new
    pgbus.define_singleton_method(:stream) { |*, **| failing }
    stub_const("Pgbus", pgbus)
    allow_any_instance_of(SlowTotalsComponent).to receive(:to_stream_replace).and_raise(RuntimeError, "render boom")

    expect { perform }.to raise_error(RuntimeError, /pg down/)
  end
end
