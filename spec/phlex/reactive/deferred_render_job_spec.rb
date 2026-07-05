# frozen_string_literal: true

require "rails_helper"

# The push lane's render job (issue #165): rebuild the component from its
# identity payload, render, and broadcast DURABLY to the one-shot stream —
# durable is what makes pgbus's since-id replay close the broadcast-before-
# subscribe race. The payload always ends with a remove of the client's
# <pgbus-stream-source> (id reactive-defer-src-<target>), so the subscription
# tears itself down with the content it delivered. A gone record / render?
# false broadcasts the CLEANUP instead (pending markers cleared client-side via
# reactive:js ops) — the shimmer must never hang.
RSpec.describe Phlex::Reactive::DeferredRenderJob do
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

  def perform(payload, target: "slow-totals", morph: false, klass: "SlowTotalsComponent")
    described_class.new.perform(klass, payload, stream_key, target, morph)
  end

  it "broadcasts the rendered replace + the source teardown, DURABLY, to the one-shot key" do
    perform({ "c" => "SlowTotalsComponent", "s" => { "value" => 9 } })

    expect(broadcasts.first).to eq({ key: stream_key, durable: true })
    html = broadcasts.last
    expect(html).to include('<turbo-stream action="replace" target="slow-totals">')
    expect(html).to include(">9<")
    expect(html).to include("data-reactive-token-value") # arrives interactive
    expect(html).to include('<turbo-stream action="remove" target="reactive-defer-src-slow-totals">')
  end

  it "honors morph mode" do
    perform({ "c" => "SlowTotalsComponent", "s" => { "value" => 9 } }, morph: true)
    expect(broadcasts.last).to include('method="morph"')
  end

  it "broadcasts cleanup (pending-clear ops + teardown) when the record is gone" do
    todo = Todo.create!(title: "gone", done: false)
    gid = todo.to_gid.to_s
    todo.destroy!

    described_class.new.perform("TodoItemComponent", { "c" => "TodoItemComponent", "gid" => gid },
      stream_key, "todo_#{todo.id}", false)

    html = broadcasts.last
    expect(html).not_to include('action="replace"')
    expect(html).to include('action="reactive:js"')
    expect(html).to include("data-reactive-defer-pending")
    expect(html).to include(%(action="remove" target="reactive-defer-src-todo_#{todo.id}"))
  end

  it "broadcasts cleanup when render? is false" do
    SlowTotalsComponent.suppressed = true
    perform({ "c" => "SlowTotalsComponent", "s" => { "value" => 9 } })

    html = broadcasts.last
    expect(html).not_to include('action="replace"')
    expect(html).to include('action="reactive:js"')
  ensure
    SlowTotalsComponent.suppressed = false
  end

  it "refuses a non-reactive class (defense in depth — job args are internal, but fail closed)" do
    expect { perform({ "c" => "Todo" }, klass: "Todo") }.to raise_error(ArgumentError, /reactive/)
    expect(broadcasts).to be_empty
  end

  it "runs on the configured defer queue" do
    expect(described_class.new.queue_name).to eq(Phlex::Reactive.defer_job_queue.to_s)
  end
end
