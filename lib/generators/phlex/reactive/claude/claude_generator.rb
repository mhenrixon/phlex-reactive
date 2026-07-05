# frozen_string_literal: true

require "rails/generators/base"
require "json"

module Phlex
  module Reactive
    module Generators
      # `rails g phlex:reactive:claude`
      #
      # Installs the phlex-reactive debugging toolkit for Claude Code inside a
      # host app (issue #168):
      #   * copies the shipped `phlex-reactive-debugging` skill into
      #     .claude/skills/ (the debugging runbook: doctor → inventory → find →
      #     browser scan → MCP)
      #   * adds the read-only MCP server to .claude/../.mcp.json — but ONLY when
      #     the file is absent (never rewrite an existing .mcp.json); otherwise it
      #     prints the snippet to add by hand.
      #
      # The skill ships INSIDE the gem (under lib/, so the gemspec packages it),
      # not as a template, so it always matches the installed gem version.
      class ClaudeGenerator < ::Rails::Generators::Base
        SKILL_NAME = "phlex-reactive-debugging"

        # The shipped skills live inside the gem under lib/phlex/reactive/claude/
        # skills/ (packaged by the gemspec). source_root points there so
        # `directory` copies the skill tree by its relative name.
        source_root File.expand_path("../../../../phlex/reactive/claude/skills", __dir__)

        # The MCP server entry a host app adds to .mcp.json. Introspection needs
        # the booted app, so the command is the rake task (not a standalone exe).
        MCP_ENTRY = {
          "mcpServers" => {
            "phlex-reactive" => {
              "command" => "bin/rails",
              "args" => ["phlex_reactive:mcp"]
            }
          }
        }.freeze

        # The shipped skill directory inside the gem (packaged under lib/).
        def self.skill_source_dir
          File.expand_path("../../../../phlex/reactive/claude/skills/#{SKILL_NAME}", __dir__)
        end

        # Copy the shipped skill into the host app's .claude/skills/.
        def install_skill
          source = self.class.skill_source_dir
          dest = File.join(".claude", "skills", SKILL_NAME)
          directory(source, dest)
        end

        # Create .mcp.json with the server entry when it's absent; otherwise print
        # the snippet (NEVER rewrite an existing .mcp.json — it may hold other
        # servers the app configured).
        def configure_mcp
          path = ".mcp.json"
          if File.exist?(File.join(destination_root, path))
            say_status :skip, "#{path} exists — add the phlex-reactive server yourself:", :yellow
            say(pretty_entry)
          else
            create_file path, "#{pretty_entry}\n"
          end
        end

        def show_post_install
          say_status :info, "phlex-reactive debugging toolkit installed for Claude Code.", :green
          say <<~MSG

            The `#{SKILL_NAME}` skill teaches the debugging workflow (doctor →
            inventory → find → browser report() → MCP). The MCP server needs the
            optional `mcp` gem — add `gem "mcp"` to your Gemfile to enable it.

            Try it:  bin/rails phlex_reactive:doctor
          MSG
        end

        private

        def pretty_entry
          JSON.pretty_generate(MCP_ENTRY)
        end
      end
    end
  end
end
