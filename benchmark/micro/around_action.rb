# frozen_string_literal: true

# Micro-bench: the component-aware around_action fold's EMPTY-STACK path (issue
# #112). Every default request (no wrapper registered) now passes through
# ActionsController#with_around_actions, whose fast path is a single
# `Array#empty?` check followed by `yield`. This isolates that per-request
# overhead against a bare `yield` — the pre-#112 shape — so the acceptance
# criterion "the empty-stack path is unchanged within noise" is a MEASURED
# before/after, not a claim.
#
# The two harness objects mirror run_action's structure with real METHODS (not
# per-call lambdas — those would add allocations the controller never pays): one
# yields straight to the inner action (pre-#112), one folds through the shipped
# empty-stack guard (#112). We reproduce the fold here (rather than drive a full
# HTTP request) so the number is the fold's cost alone, not the Rails stack + DB
# that dominate a real request.
#
#   ruby benchmark/micro/around_action.rb

require_relative "../support/boot"

# The two measured paths, as real methods (not per-call lambdas — those would add
# allocations the controller never pays). Both take an explicit block argument, so
# the only difference between them is the fold guard the controller actually runs.
module AroundActionBench
  module_function

  # BEFORE (#112): the endpoint yielded straight to the (transactioned) action.
  def bare
    yield
  end

  # AFTER (#112): with_around_actions with an EMPTY stack — the production default.
  # `return yield if stack.empty?` is the whole hot path (byte-identical to the
  # controller's fold); no ActionContext is built, no wrapper runs. Reads the real
  # (empty) config stack so Array#empty? measures the shipped object.
  def empty_fold(&block)
    stack = Phlex::Reactive.around_actions
    return yield if stack.empty?

    # Unreachable in this bench (stack is empty) — present so the measured method
    # is the same shape as the controller's fold.
    stack.reduce(block) { |inner, w| -> { w.call(&inner) } }.call
  end
end

Phlex::Reactive.reset_around_actions!
inner = -> { 42 }

BenchSupport.header("around_action: empty-stack fold vs bare yield (per-request hot path)")
BenchSupport.ips do
  it.report("bare yield (pre-#112)") { AroundActionBench.bare(&inner) }
  it.report("empty-stack fold (#112)") { AroundActionBench.empty_fold(&inner) }
end

BenchSupport.header("around_action allocations (per call)")
BenchSupport.allocations("bare yield (pre-#112)") { AroundActionBench.bare(&inner) }
BenchSupport.allocations("empty-stack fold (#112)") { AroundActionBench.empty_fold(&inner) }
