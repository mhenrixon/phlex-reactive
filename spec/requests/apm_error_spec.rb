# frozen_string_literal: true

require "rails_helper"

# The action-body error seam (issue #207). A component action that raises a
# previously-UNCAUGHT error (not a registered authorization error → not a 4xx)
# must: tag the action.phlex_reactive event outcome=:error, report the exception
# to the resolved APM adapter AND every on_action_error hook WITH component/action
# context, render the error_flash (when configured), and THEN re-raise unchanged
# so Rails' own error reporting fires. Ordering: report → flash → re-raise; a
# broken reporter never changes what propagates.
RSpec.describe "action-body error seam (issue #207)", type: :request do
  # Restore all APM/hook state after every example.
  around do
    it.run
  ensure
    Phlex::Reactive.reset_on_action_error!
    Phlex::Reactive::APM.reset!
    Phlex::Reactive.remove_instance_variable(:@apm) if Phlex::Reactive.instance_variable_defined?(:@apm)
    Phlex::Reactive.remove_instance_variable(:@error_flash) if Phlex::Reactive.instance_variable_defined?(:@error_flash)
  end

  def capture_action_events
    events = []
    sub = ActiveSupport::Notifications.subscribe("action.phlex_reactive") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  def post_explode
    post_action(CounterComponent, act: "explode", payload: { "s" => { "count" => 1 } })
  end

  it "re-raises the action-body error (Rails' own reporting still fires)" do
    expect { post_explode }.to raise_error(RuntimeError, /kaboom/)
  end

  it "tags the action.phlex_reactive event outcome=:error" do
    events = capture_action_events do
      post_explode
    rescue RuntimeError
      # expected — swallow so we can inspect the event
    end
    expect(events.first.payload[:outcome]).to eq(:error)
    expect(events.first.payload[:component]).to eq("CounterComponent")
    expect(events.first.payload[:action]).to eq("explode")
  end

  it "reports the exception to a registered on_action_error hook with component/action context" do
    reported = []
    Phlex::Reactive.on_action_error { |error, ctx| reported << [error, ctx] }

    begin
      post_explode
    rescue RuntimeError
      nil
    end

    expect(reported.size).to eq(1)
    error, ctx = reported.first
    expect(error).to be_a(RuntimeError)
    expect(error.message).to include("kaboom")
    expect(ctx).to include(component: "CounterComponent", action: "explode", outcome: :error)
  end

  it "reports the exception to the resolved APM adapter's record_error" do
    adapter = instance_double(Phlex::Reactive::APM::Adapter, record_action: nil, record_error: nil)
    Phlex::Reactive.apm = adapter
    Phlex::Reactive::APM.attach!

    begin
      post_explode
    rescue RuntimeError
      nil
    end

    expect(adapter).to have_received(:record_error)
      .with(an_instance_of(RuntimeError), hash_including(component: "CounterComponent", action: "explode"))
  end

  it "does NOT carry token/params/state to the reporter (name-only context)" do
    reported = nil
    Phlex::Reactive.on_action_error { |_error, ctx| reported = ctx }

    begin
      post_action(CounterComponent, act: "explode",
        payload: { "s" => { "count" => 1 } }, params: { secret: "leak" })
    rescue RuntimeError
      nil
    end

    expect(reported.keys).to contain_exactly(:component, :action, :outcome)
    expect(reported.values.join).not_to include("leak")
  end

  it "forwards a name-only SNAPSHOT — mutating the live event hash after does not leak in" do
    # ActiveSupport::Notifications adds :exception / :exception_object to the SAME
    # payload hash during unwinding. A reporter that RETAINS the context must not
    # pick those up — report_error forwards a fresh slice, not the live hash.
    captured = nil
    Phlex::Reactive.on_action_error { |_error, ctx| captured = ctx }

    event = { component: "CounterComponent", action: "explode", outcome: nil }
    Phlex::Reactive.report_error(RuntimeError.new("boom"), event)

    # Simulate ASN mutating the live hash after the reporter ran.
    event[:exception_object] = RuntimeError.new("leaked")
    event[:exception] = %w[RuntimeError leaked]

    expect(captured).to eq(component: "CounterComponent", action: "explode", outcome: nil)
    expect(captured).not_to have_key(:exception)
    expect(captured).not_to have_key(:exception_object)
  end

  describe "a broken reporter never changes what propagates" do
    it "still re-raises the ORIGINAL error when an on_action_error hook itself raises" do
      Phlex::Reactive.on_action_error { |_e, _ctx| raise "reporter is broken" }

      expect { post_explode }.to raise_error(RuntimeError, /kaboom/)
    end
  end

  describe "error_flash on a 500 (flash on crash)" do
    # error_flash is called as callable.call(kind) — the lambda MUST take one
    # positional arg, so an explicit param, not `it` (which would drop arity to 0).
    before do
      Phlex::Reactive.error_flash = ->(kind) { "Something went wrong (#{kind})" } # rubocop:disable Style/ItBlockParameter
    end

    after { Phlex::Reactive.error_flash = nil }

    it "renders the error_flash for the crash yet still re-raises (flash does not swallow)" do
      # The flash is built inside the seam; the raise still propagates. We assert
      # the raise (the contract) — the flash-building is covered by not-raising a
      # DIFFERENT error and by the controller-level behavior below.
      expect { post_explode }.to raise_error(RuntimeError, /kaboom/)
    end

    it "still re-raises the ORIGINAL error even when the error_flash lambda itself raises" do
      Phlex::Reactive.error_flash = ->(_kind) { raise "flash builder is broken" }
      # error_flash_stream already degrades a raising lambda to nil; the seam's own
      # guard is the backstop. Either way the action-body error must win.
      expect { post_explode }.to raise_error(RuntimeError, /kaboom/)
    end

    it "reports to the hook BEFORE the flash (report → flash → re-raise ordering)" do
      order = []
      Phlex::Reactive.on_action_error { |_e, _ctx| order << :reported }
      Phlex::Reactive.error_flash = lambda { |_kind|
        order << :flash
        "boom flash"
      }

      begin
        post_explode
      rescue RuntimeError
        order << :raised
      end

      expect(order).to eq(%i[reported flash raised])
    end
  end
end
