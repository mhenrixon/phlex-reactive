# frozen_string_literal: true

require "spec_helper"

# The system suite drives the REAL browser via a vendored copy of the client
# controller at spec/dummy/public/vendor/reactive_controller.js (importmap-pinned
# in the dummy layout). If that copy drifts from the shipped source, the browser
# specs validate stale code — exactly how the pgbus connection-id logic and, later,
# the issue #8 rich-text collection fix could have gone untested. This guard makes
# drift a hard failure: keep the vendored copy byte-identical to source.
RSpec.describe "vendored client controller" do
  root = File.expand_path("../..", __dir__)
  source = File.join(root, "app/javascript/phlex/reactive/reactive_controller.js")
  vendored = File.join(root, "spec/dummy/public/vendor/reactive_controller.js")

  it "is byte-identical to the shipped source (no drift)" do
    expect(File.read(vendored)).to eq(File.read(source)),
      "spec/dummy/public/vendor/reactive_controller.js has drifted from the source " \
      "app/javascript/phlex/reactive/reactive_controller.js. Re-sync it (the system " \
      "suite runs the vendored copy):\n\n" \
      "  cp app/javascript/phlex/reactive/reactive_controller.js " \
      "spec/dummy/public/vendor/reactive_controller.js"
  end
end
