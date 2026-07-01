# frozen_string_literal: true

# Run the browser (system) suite at each responsive viewport, so layout
# regressions that only show on a phone/tablet are caught. Mirrors the
# puma/falcon server matrix. CI runs these; run locally with:
#   bundle exec rake spec:system_screens
namespace :spec do
  desc 'Run the system suite at mobile, tablet, and desktop viewports'
  task :system_screens do # rubocop:disable Rails/RakeEnvironment
    %w[mobile tablet desktop].each do |screen|
      puts "\n=== system specs @ #{screen} ==="
      sh({ 'CAPYBARA_SCREEN' => screen }, 'bundle', 'exec', 'rspec', 'spec/system')
    end
  end
end
