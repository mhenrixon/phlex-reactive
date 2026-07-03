# frozen_string_literal: true

require 'rails_helper'

# The drift-proof embed wrapper for the example pages: it renders a REAL reactive
# component live AND reads that same component's own source file for the code
# block, so the demo and the shown code can never diverge (the #148/DemoPanel
# pattern, made reusable on a docs page).
RSpec.describe Views::Examples::LiveExample, type: :request do
  # Render the Phlex wrapper the way a docs page does — through the configured
  # renderer's view context so dom_id/url_for/csrf work during the reactive
  # component's render.
  def render_wrapper(**)
    Phlex::Reactive.renderer.render(described_class.new(**))
  end

  it 'renders the live component (the demo round-trips)' do
    html = render_wrapper(component: CounterComponent.new(count: 0))

    # The live demo box wraps the real component, which self-targets its own id.
    expect(html).to include('data-testid="live-example-demo"')
    expect(html).to include('id="counter"')
    expect(html).to include('data-testid="inc"')
  end

  it 'reads the component source live from its own file (drift-proof)' do
    html = render_wrapper(component: CounterComponent.new(count: 0))

    # The code block shows the ACTUAL class source read off disk — not a
    # hand-copied snippet — so a change to the component updates the docs too.
    # (Rouge wraps each token in a <span>, so assert on identifiers that survive
    # highlighting as a single token, not multi-token phrases.)
    expect(html).to include('CounterComponent')
    expect(html).to include('reactive_state')
    expect(html).to include('bump_via_morph')
  end

  it 'passes an explicit source through verbatim when given (multi-class port)' do
    html = render_wrapper(component: CounterComponent.new(count: 0),
                          source: '# THREE collaborating classes shown together')

    expect(html).to include('THREE collaborating classes')
    # The explicit source wins — the file is not read.
    expect(html).not_to include('reactive_state')
  end

  it 'labels the source with a copy-pasteable filename' do
    html = render_wrapper(component: CounterComponent.new(count: 0),
                          filename: 'app/components/counter_component.rb')

    expect(html).to include('app/components/counter_component.rb')
  end
end
