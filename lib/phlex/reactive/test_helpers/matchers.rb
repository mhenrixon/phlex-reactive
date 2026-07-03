# frozen_string_literal: true

# RSpec matchers for reactive action Results (issue #110). Loaded lazily by
# Phlex::Reactive::TestHelpers only when RSpec is present, so the gem never hard
# depends on RSpec — a Minitest app mixes in TestHelpers and simply asserts on
# Result predicates (result.replace?, result.streams) directly.
#
#   expect(run_reactive(component, :toggle)).to have_reactive_replace(component)
#   expect(run_reactive(component, :archive)).to have_reactive_remove(component)
#   expect(run_reactive(component, :increment)).to have_reactive_token_for(component)
#
# Each matcher accepts a component INSTANCE or a bare DOM id String, and prints a
# diff worth reading on failure (the stream actions/targets it actually saw).
#
# Style/ItBlockParameter is disabled FILE-WIDE on purpose: in RSpec::Matchers
# .define, the `do |arg|` param is the EXPECTED value and `match do |actual|` the
# MATCHED value — two distinct objects. Collapsing either to the implicit `it`
# (as the cop's autocorrect does) conflates them and silently guts the matcher.
# rubocop:disable Style/ItBlockParameter
module Phlex
  module Reactive
    module TestHelpers
      # The DOM id a matcher argument targets: a String is the id verbatim; a
      # component instance answers #id.
      def self.matcher_target_id(component_or_id)
        component_or_id.is_a?(::String) ? component_or_id : component_or_id.id
      end

      # A compact listing of the turbo-stream action="..." target="..." pairs in
      # `streams` — the readable core of every failure message.
      def self.describe_streams(streams)
        pairs = streams.map do |stream|
          open_tag = stream[/<turbo-stream\b[^>]*>/] || stream
          action = open_tag[/\baction="([^"]+)"/, 1] || "?"
          target = open_tag[/\btarget="([^"]+)"/, 1]
          target ? "#{action}->##{target}" : action
        end
        pairs.empty? ? "(no streams)" : pairs.join(", ")
      end

      # True when a turbo-stream's opening tag re-renders `id` with one of
      # `actions` at that target. Shared by the replace/remove target checks.
      def self.stream_action_targets?(stream, actions, id)
        open_tag = stream[/<turbo-stream\b[^>]*>/] || ""
        actions.include?(open_tag[/\baction="([^"]+)"/, 1]) &&
          open_tag.include?(%(target="#{ERB::Util.html_escape(id)}"))
      end
    end
  end
end

RSpec::Matchers.define :have_reactive_replace do |component_or_id|
  match do |result|
    @id = Phlex::Reactive::TestHelpers.matcher_target_id(component_or_id)
    @streams = result.streams
    result.replace? &&
      @streams.any? { |stream| Phlex::Reactive::TestHelpers.stream_action_targets?(stream, %w[replace update], @id) }
  end

  failure_message do
    "expected the reactive Result to replace ##{@id}, " \
      "but it did not (streams: #{Phlex::Reactive::TestHelpers.describe_streams(@streams)})"
  end

  failure_message_when_negated do
    "expected the reactive Result NOT to replace ##{@id}, but it did " \
      "(streams: #{Phlex::Reactive::TestHelpers.describe_streams(@streams)})"
  end
end

RSpec::Matchers.define :have_reactive_remove do |component_or_id|
  match do |result|
    @id = Phlex::Reactive::TestHelpers.matcher_target_id(component_or_id)
    @streams = result.streams
    result.remove? &&
      @streams.any? { |stream| Phlex::Reactive::TestHelpers.stream_action_targets?(stream, %w[remove], @id) }
  end

  failure_message do
    "expected the reactive Result to remove ##{@id}, " \
      "but it did not (streams: #{Phlex::Reactive::TestHelpers.describe_streams(@streams)})"
  end

  failure_message_when_negated do
    "expected the reactive Result NOT to remove ##{@id}, but it did " \
      "(streams: #{Phlex::Reactive::TestHelpers.describe_streams(@streams)})"
  end
end

# Pins the #44/#46 token-refresh regression class: a reply that fails to roll the
# component's signed token forward makes the next action reject silently. This
# matcher asserts a fresh data-reactive-token-value for the component IS present.
RSpec::Matchers.define :have_reactive_token_for do |component_or_id|
  match do |result|
    @id = Phlex::Reactive::TestHelpers.matcher_target_id(component_or_id)
    @streams = result.streams
    target = %(target="#{ERB::Util.html_escape(@id)}")
    @streams.any? { |stream| stream.include?("data-reactive-token-value") && stream.include?(target) }
  end

  failure_message do
    "expected the reactive Result to carry a fresh signed token for ##{@id} " \
      "(a data-reactive-token-value at its target), but none was present — the next action " \
      "from ##{@id} would be rejected with a stale token (streams: " \
      "#{Phlex::Reactive::TestHelpers.describe_streams(@streams)})"
  end

  failure_message_when_negated do
    "expected the reactive Result NOT to carry a fresh token for ##{@id}, but it did"
  end
end
# rubocop:enable Style/ItBlockParameter
