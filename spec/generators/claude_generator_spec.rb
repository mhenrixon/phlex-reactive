# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "generators/phlex/reactive/claude/claude_generator"

# `rails g phlex:reactive:claude` installs the debugging toolkit (issue #168):
# it copies the shipped skill into .claude/skills/ and writes the MCP server
# entry into .mcp.json — but only when .mcp.json is absent (it never rewrites an
# existing one).
RSpec.describe Phlex::Reactive::Generators::ClaudeGenerator do
  let(:tmp) { Rails.root.join("tmp/claude-generator-spec") }

  before { FileUtils.rm_rf(tmp) }
  after { FileUtils.rm_rf(tmp) }

  def run!
    described_class.start([], destination_root: tmp)
  end

  it "copies the phlex-reactive-debugging skill into .claude/skills/" do
    run!
    skill = tmp.join(".claude/skills/phlex-reactive-debugging/SKILL.md")
    expect(File).to exist(skill)
    expect(File.read(skill)).to include("Debugging phlex-reactive")
  end

  context "when .mcp.json is absent" do
    it "creates it with the phlex-reactive server entry" do
      run!
      mcp = tmp.join(".mcp.json")
      expect(File).to exist(mcp)
      parsed = JSON.parse(File.read(mcp))
      server = parsed.dig("mcpServers", "phlex-reactive")
      expect(server["command"]).to eq("bin/rails")
      expect(server["args"]).to eq(["phlex_reactive:mcp"])
    end
  end

  context "when .mcp.json already exists" do
    before do
      FileUtils.mkdir_p(tmp)
      File.write(tmp.join(".mcp.json"), JSON.pretty_generate({ "mcpServers" => { "other" => { "command" => "x" } } }))
    end

    it "does NOT rewrite it (prints the snippet instead)" do
      expect { run! }.to output(/phlex_reactive:mcp/).to_stdout
      parsed = JSON.parse(File.read(tmp.join(".mcp.json")))
      # The pre-existing server survives untouched; phlex-reactive is NOT added.
      expect(parsed["mcpServers"]).to have_key("other")
      expect(parsed["mcpServers"]).not_to have_key("phlex-reactive")
    end
  end

  it "tells the user the MCP server needs the optional mcp gem" do
    expect { run! }.to output(/mcp.*gem|gem "mcp"/i).to_stdout
  end
end
