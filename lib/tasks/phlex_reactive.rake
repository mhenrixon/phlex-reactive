# frozen_string_literal: true

# Rails engines auto-load rake tasks under lib/tasks — no engine.rb change is
# needed for `bin/rails phlex_reactive:doctor` to appear in the host app.
namespace :phlex_reactive do
  desc "Validate the phlex-reactive install (route, Stimulus, verifier, components) — issue #106"
  task doctor: :environment do
    # Doctor.run eager-loads so the component registry is populated, prints the
    # ✓/✗/? report (with a fix per failure), and returns false if any check
    # FAILED (advisory `?` lines don't count) — abort so CI / a setup script can
    # gate on `bin/rails phlex_reactive:doctor`.
    abort unless Phlex::Reactive::Doctor.run
  end
end
