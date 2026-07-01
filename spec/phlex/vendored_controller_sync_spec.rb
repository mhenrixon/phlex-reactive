# frozen_string_literal: true

require "spec_helper"

# The system suite drives the REAL browser via vendored copies of the client
# modules under spec/dummy/public/vendor (importmap-pinned in the dummy layout).
# If a copy drifts from the shipped source, the browser specs validate stale code
# — exactly how the pgbus connection-id logic and, later, the issue #8 rich-text
# collection fix could have gone untested. This guard makes drift a hard failure:
# keep every vendored copy byte-identical to its source under app/javascript.
RSpec.describe "vendored client modules" do
  root = File.expand_path("../..", __dir__)

  # Each client module the system suite serves from spec/dummy/public/vendor.
  vendored_modules = %w[
    reactive_controller.js
    confirm.js
    compute.js
  ]

  # Explicit block param (not `it`): the block body defines RSpec `it` examples,
  # so naming the param `it` would shadow RSpec's example method.
  # rubocop:disable Style/ItBlockParameter
  vendored_modules.each do |filename|
    it "#{filename} is byte-identical to the shipped source (no drift)" do
      source = File.join(root, "app/javascript/phlex/reactive", filename)
      vendored = File.join(root, "spec/dummy/public/vendor", filename)

      expect(File.read(vendored)).to eq(File.read(source)),
        "spec/dummy/public/vendor/#{filename} has drifted from the source " \
        "app/javascript/phlex/reactive/#{filename}. Re-sync it (the system suite " \
        "runs the vendored copy):\n\n  " \
        "cp app/javascript/phlex/reactive/#{filename} spec/dummy/public/vendor/#{filename}"
    end
  end
  # rubocop:enable Style/ItBlockParameter
end
