# frozen_string_literal: true

require_relative "lib/phlex/reactive/version"

Gem::Specification.new do |spec|
  spec.name = "phlex-reactive"
  spec.version = Phlex::Reactive::VERSION
  spec.authors = ["Mikael Henriksson"]
  spec.email = ["mikael@mhenrixon.com"]

  spec.summary = "Reactive Phlex components for Rails — Livewire-style actions and live cross-tab updates, no Stimulus boilerplate."
  spec.description = <<~DESC
    phlex-reactive makes Phlex components reactive without writing Stimulus
    controllers or hand-picking Turbo Stream targets. Declare actions in Ruby;
    a single generic client runtime turns clicks and form input into a server
    round trip that re-renders the component and morphs it back in. Components
    self-target by a stable DOM id, so the same unit re-renders for client
    actions AND server-pushed broadcasts. State lives in the database behind a
    signed identity — no attacker-controlled snapshot. Pairs with pgbus for
    reliable, transactional, reconnect-safe live updates with no Action Cable
    and no Redis.
  DESC
  spec.homepage = "https://github.com/mhenrixon/phlex-reactive"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mhenrixon/phlex-reactive/tree/main"
  spec.metadata["changelog_uri"] = "https://github.com/mhenrixon/phlex-reactive/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |f|
      f.start_with?("app/", "config/", "lib/") ||
        f == "CHANGELOG.md" || f == "LICENSE.txt" || f == "README.md"
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "globalid", "~> 1.0"
  spec.add_dependency "phlex-rails", ">= 2.0", "< 3"
  spec.add_dependency "railties", ">= 7.1", "< 9.0"
  spec.add_dependency "turbo-rails", ">= 1.5", "< 3"
  spec.add_dependency "zeitwerk", "~> 2.6"
end
