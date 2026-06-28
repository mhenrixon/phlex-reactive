# frozen_string_literal: true

# Exercises the debounce option (issue #17). The `query` input dispatches a
# debounced `search` action; each run bumps a `runs` counter and echoes the last
# query. A burst of rapid input must coalesce into ONE run (one increment), not
# one per keystroke.
class DebounceComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_state :query, :runs

  action :search, params: { query: :string }

  def initialize(query: "", runs: 0)
    @query = query
    @runs = runs
  end

  def id = "debounce"

  def search(query:)
    @query = query
    @runs += 1
  end

  def view_template
    div(id:, **reactive_attrs) do
      input(**mix(on(:search, event: "input", debounce: 150),
        name: "query", value: @query, data: { testid: "query" }))
      span(data: { testid: "runs" }) { @runs.to_s }
      span(data: { testid: "echo" }) { @query }
    end
  end
end
