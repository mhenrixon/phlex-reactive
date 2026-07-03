# frozen_string_literal: true

require "rails_helper"

# The doctor validates the WHOLE install with ✓/✗/? checks (issue #106). It
# boots against the dummy app — a correctly-wired install — so the happy path is
# all-green, and inline fixtures exercise the two component findings that don't
# need a second booted app (a declared-but-missing action, and a state-backed
# class with no #id).
RSpec.describe Phlex::Reactive::Doctor do
  subject(:doctor) { described_class.new }

  # A Check is the small object the issue specifies: it answers [status, message,
  # fix]. status is one of :ok/:fail/:unknown; a passing check has no fix.
  describe "a check" do
    it "exposes status, message and fix" do
      check = Phlex::Reactive::Doctor::Check.new(:ok, "all good", fix: nil)
      expect(check.status).to eq(:ok)
      expect(check.message).to eq("all good")
      expect(check.fix).to be_nil
      expect(check).to be_ok
    end

    it "carries a fix on failure" do
      check = Phlex::Reactive::Doctor::Check.new(:fail, "broken", fix: "do this")
      expect(check).not_to be_ok
      expect(check.fix).to eq("do this")
    end
  end

  describe "#checks (happy path against the dummy app)" do
    before { Rails.application.eager_load! }

    it "returns a check for every section" do
      names = doctor.checks.map(&:name)
      expect(names).to include(
        :route, :stimulus, :csrf, :verifier, :base_controller, :actions, :ids
      )
    end

    it "passes the route check (the endpoint resolves)" do
      route = doctor.checks.find { it.name == :route }
      expect(route).to be_ok
    end

    it "passes the verifier round-trip check" do
      verifier = doctor.checks.find { it.name == :verifier }
      expect(verifier).to be_ok
    end

    it "passes the base_controller_name constantize check" do
      base = doctor.checks.find { it.name == :base_controller }
      expect(base).to be_ok
    end

    it "passes the declared-action-has-a-method check (every dummy action maps)" do
      actions = doctor.checks.find { it.name == :actions }
      expect(actions).to be_ok
    end

    it "passes the #id check (dummy classes define #id or are record-backed)" do
      ids = doctor.checks.find { it.name == :ids }
      expect(ids).to be_ok
    end

    it "marks csrf ADVISORY (unknown, not fail) — Phlex-layout apps have no ERB layout" do
      csrf = doctor.checks.find { it.name == :csrf }
      # Never a hard fail — a Phlex-layout app (this gem's audience) would
      # false-flag. It is :ok when a csrf_meta_tags reference is found, else :unknown.
      expect(csrf.status).to be_in(%i[ok unknown])
    end

    it "has no failing checks on a correctly-wired install" do
      expect(doctor.checks.reject(&:ok?).select { it.status == :fail }).to be_empty
    end

    # The whole-app checks scan the Streamable registry, which also holds every
    # Class.new fixture the test suite defines — many deliberately state-backed
    # without #id or with undeclared actions. The doctor validates ONLY
    # constant-resolvable components (a class the endpoint could actually rebuild
    # via safe_constantize), so a faked-`def self.name` fixture never leaks in and
    # red-flags a correctly-wired app.
    it "ignores registry classes whose name does not resolve to the class itself" do
      Class.new(ApplicationComponent) do
        include Phlex::Reactive::Component

        # "Phantom::StateWidget" is not a real constant, so the doctor skips it.
        def self.name = "Phantom::StateWidget"

        reactive_state :n
        # :ghost has no method and the class has no #id — it would fail BOTH
        # component checks if the doctor scanned it.
        action :ghost
        def initialize(n: 0) = (@n = n)
      end

      expect(doctor.checks.select { it.status == :fail }).to be_empty
    end
  end

  describe "the declared-action-has-a-method check (broken fixture)" do
    # A component that declares an action with NO matching public method — the
    # endpoint would 500 on public_send. Defined inline so no second app is booted.
    let(:broken) do
      Class.new(ApplicationComponent) do
        include Phlex::Reactive::Component

        reactive_state :n
        action :ghost # no `def ghost`
        def initialize(n: 0) = (@n = n)
        def id = "broken-action"
      end
    end

    it "flags the missing method" do
      check = doctor.action_check([broken])
      expect(check).not_to be_ok
      expect(check.status).to eq(:fail)
      expect(check.message).to include("ghost")
    end

    it "passes when every declared action has a method" do
      ok = Class.new(ApplicationComponent) do
        include Phlex::Reactive::Component

        reactive_state :n
        action :bump
        def initialize(n: 0) = (@n = n)
        def id = "ok-action"
        def bump = @n += 1
      end
      expect(doctor.action_check([ok])).to be_ok
    end
  end

  describe "the #id override check (broken fixture)" do
    # A state-backed class on the DEFAULT #id still raises NotImplementedError at
    # render — the finding. A record-backed class on the default is FINE (#81).
    let(:state_without_id) do
      Class.new(ApplicationComponent) do
        include Phlex::Reactive::Component

        reactive_state :n
        action :bump
        def initialize(n: 0) = (@n = n)
        def bump = @n += 1
        # NO `def id` — inherits Streamable's default, which raises for state-backed.
      end
    end

    let(:state_with_id) do
      Class.new(ApplicationComponent) do
        include Phlex::Reactive::Component

        reactive_state :n
        def initialize(n: 0) = (@n = n)
        def id = "has-id"
      end
    end

    it "flags a state-backed class that never overrides #id" do
      check = doctor.id_check([state_without_id])
      expect(check).not_to be_ok
      expect(check.status).to eq(:fail)
    end

    it "passes a state-backed class that defines #id" do
      expect(doctor.id_check([state_with_id])).to be_ok
    end

    it "does NOT flag a record-backed class on the default #id (issue #81)" do
      record_backed = Class.new(ApplicationComponent) do
        include Phlex::Reactive::Component

        reactive_record :todo
        def initialize(todo:) = (@todo = todo)
        # no `def id` — record-backed default is FINE, not a finding.
      end
      expect(doctor.id_check([record_backed])).to be_ok
    end
  end

  describe "output rendering" do
    before { Rails.application.eager_load! }

    it "renders stable plain text (no ANSI color codes) with ✓/✗/? glyphs" do
      output = doctor.report
      expect(output).not_to match(/\e\[[0-9;]*m/) # no ANSI escapes
      expect(output).to match(/[✓✗?]/)
    end

    it "prints the fix line for each failing check" do
      broken = Class.new(ApplicationComponent) do
        include Phlex::Reactive::Component

        reactive_state :n
        action :ghost
        def initialize(n: 0) = (@n = n)
        def id = "x"
      end
      check = doctor.action_check([broken])
      output = doctor.render_check(check)
      expect(output).to include("✗")
      expect(output).to include(check.fix)
    end
  end
end
