# frozen_string_literal: true

# System/browser test helpers for reactive components (issue #201). Loaded lazily
# by Phlex::Reactive::TestHelpers ONLY when Capybara is present (the pgbus/mcp
# optional-require precedent), so the gem never hard depends on Capybara and this
# module stays out of the request/unit path.
#
# Mix it into your system examples from rails_helper:
#
#   RSpec.configure do |c|
#     c.include Phlex::Reactive::TestHelpers::System, type: :system
#   end
#
# It is built on the GLOBAL reactive-activity signal the client runtime exposes:
# a <html data-reactive-active> marker present while ANY reactive operation (a
# dispatch round trip OR a deferred render) is in flight, cleared when the whole
# layer settles. That is the clean primitive to wait on — instead of each spec
# scraping the union of per-root busy/pending/seed selectors, or holding a node
# that a morph detaches (StaleReferenceError).
#
#   wait_for_reactive                       # block until the layer is idle
#   expect(page).to have_reactive_value("total", "6")  # a field, re-resolved each poll
#   expect(page).to have_reactive_text("recap", "6 items") # a mirror node, re-resolved
#
# All three re-resolve the DOM every poll cycle (Capybara's waiting behavior), so
# a compute re-seed / morph / in-flight round trip that REPLACES the node after
# the triggering action returns can never surface a StaleReferenceError or read a
# transient blank — the matcher waits for the value to SETTLE.
module Phlex
  module Reactive
    module TestHelpers
      module System
        # The <html> marker the client sets while the reactive layer is busy. Kept
        # in lockstep with reactive_controller.js's ACTIVE_ATTR — the ONE selector
        # every wait keys off. A [data-reactive-active] presence check is the system
        # twin of wait_for_turbo watching the Turbo progress bar.
        ACTIVE_MARKER = "data-reactive-active"

        # Block until the reactive layer is IDLE — every dispatch round trip and
        # deferred render has settled and the <html data-reactive-active> marker is
        # gone. The system-test twin of wait_for_turbo (which watches the Turbo
        # progress bar, NOT a reactive morph/seed, so it can't cover this).
        #
        # Implemented as a Capybara WAITING assertion (have_no_css on the document
        # element with the default max wait), so it re-checks the live DOM each poll
        # and raises a readable Capybara::ElementNotFound-style error if the layer
        # never settles inside `timeout` — never a bare sleep, never a stale read.
        #
        # `timeout:` overrides Capybara.default_max_wait_time for a slow operation
        # (a deferred render behind a real job). Returns nil; call it as a barrier
        # BEFORE asserting a settled value if you are not already using one of the
        # waiting matchers below.
        def wait_for_reactive(timeout: nil)
          # Scope the check to <html> via the :xpath "/html" so the marker is read
          # on the document element the client writes it to — not a descendant.
          # assert_no_selector WAITS (retries) until the marker clears or the wait
          # budget elapses; a persistent marker fails LOUDLY with Capybara's own
          # timeout error rather than a silent pass. Called on `page` (the current
          # session) so it works regardless of whether the example group mixed in
          # Capybara::DSL.
          page.assert_no_selector(:xpath, "/html[@#{ACTIVE_MARKER}]", **wait_option(timeout))
          nil
        end

        # Assert (waiting) that the field with DOM id `id` has value `value`,
        # RE-RESOLVING the field by its id on every poll. Use it as the barrier for
        # a value that settles a beat after the triggering action — a reactive_compute
        # re-seed or a morph replaces the input node AFTER the action returns, so a
        # node captured by `find` would go stale; keying on the id and letting
        # Capybara re-query each cycle is immune to that.
        #
        #   expect(page).to have_reactive_value("total", "6")
        #
        # A thin, intention-revealing wrapper over Capybara's field matcher scoped
        # by id — the value the app is waiting on, named for what it is. The
        # `have_` prefix is Capybara-matcher convention (have_field/have_css), NOT a
        # predicate — hence the PredicatePrefix disable, mirroring matchers.rb.
        # rubocop:disable Naming/PredicatePrefix
        def have_reactive_value(id, value, **)
          have_field(id, with: value, **)
        end

        # Assert (waiting) that the node with DOM id `id` has TEXT `value`,
        # re-resolving by id each poll — the mirror/recap twin of
        # have_reactive_value for a text sink (a reactive_compute `text:`/mirror
        # target, a recap node) rather than a form field.
        #
        #   expect(page).to have_reactive_text("recap", "6 items")
        def have_reactive_text(id, value, **)
          have_css("##{id}", text: value, **)
        end
        # rubocop:enable Naming/PredicatePrefix

        private

        # Fold an explicit `timeout:` into Capybara's `wait:` option, or omit it so
        # Capybara's configured default applies. Kept tiny so every waiter shares
        # one timeout convention.
        def wait_option(timeout)
          timeout.nil? ? {} : { wait: timeout }
        end
      end
    end
  end
end
