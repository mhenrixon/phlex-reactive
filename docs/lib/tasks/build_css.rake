# frozen_string_literal: true

# Build the daisyUI/Tailwind stylesheet into app/assets/builds/application.css so
# Propshaft can serve it. The build output is gitignored, so it must run as part
# of `assets:precompile` (production / Docker) — `bin/dev` runs the watch variant
# in development instead. `bun run build:css` shells out to bin/build-css, which
# resolves the daisyui + docs-kit gem @source globs so Tailwind scans them.
namespace :css do
  desc "Build the Tailwind + daisyUI stylesheet via bun"
  task build: :environment do
    sh "bun run build:css"
  end
end

# Ensure CSS is compiled before fingerprinting assets.
Rake::Task["assets:precompile"].enhance(["css:build"]) if Rake::Task.task_defined?("assets:precompile")
