# frozen_string_literal: true

module RuboCop
  module Cop
    module DocsKit
      # Enforces the kit helper form over `render <Kit>::<Class>.new(...)`.
      #
      # The docs-kit `DocsUI` module and the `DaisyUI` gem are both extended with
      # `Phlex::Kit`, which defines a singleton method per component class. That
      # makes `DocsUI::Code(...)` equivalent to `render DocsUI::Code.new(...)` but
      # terser and consistent. Adapted from cosmos' Cosmos/RenderComponentPreferred.
      #
      # @example
      #   # bad
      #   render DocsUI::Code.new(source, filename: "a.rb")
      #   render DocsUI::Section.new("Title") { ... }
      #   render DaisyUI::Button.new(:primary) { "Save" }
      #
      #   # good
      #   DocsUI::Code(source, filename: "a.rb")
      #   DocsUI::Section("Title") { ... }
      #   DaisyUI::Button(:primary) { "Save" }
      #
      # The cop keeps the namespace prefix (`DocsUI::Code(...)` rather than
      # `Code(...)`) because the unqualified helper may resolve to a different kit
      # depending on inclusion order. Keeping the prefix makes the rewrite
      # mechanically safe in every rendering context.
      #
      # Contexts the cop does NOT fire in:
      # - `render <class-method-call>` like `render UI::Modal.clear` — not a .new.
      # - elements of a `turbo_stream: [...]` array — class-method calls that
      #   return Turbo Stream payloads, not `.new` component instances.
      class RenderComponentPreferred < Base
        extend AutoCorrector

        MSG = "Use `%<suggestion>s` instead of `%<original>s`."

        # Kit modules recognised by the cop.
        KIT_MODULES = %w[
          DocsUI
          DaisyUI
        ].to_set.freeze

        # `render Kit::Class.new(args)` — plain send.
        def_node_matcher :render_new_send, <<~PATTERN
          (send nil? :render $(send $const :new ...))
        PATTERN

        # `render Kit::Class.new(args) { ... }` — brace block glued onto .new.
        def_node_matcher :render_new_block, <<~PATTERN
          (send nil? :render (block $(send $const :new ...) _ _))
        PATTERN

        def on_send(node)
          return if inside_array_literal?(node)
          return unless node.arguments.length == 1

          brace_block_node = nil
          match = render_new_send(node)
          if match.nil?
            block_match = render_new_block(node)
            return unless block_match

            new_call_node, const_node = block_match
            brace_block_node = node.arguments.first
          else
            new_call_node, const_node = match
          end

          namespace = kit_namespace(const_node)
          return unless namespace

          parent = node.parent
          outer_node = if parent&.block_type? && parent.send_node == node
                         parent
                       else
                         node
                       end

          suggestion = build_helper_call(new_call_node, const_node, outer_node, brace_block_node)
          helper_headline = helper_headline(new_call_node, const_node)
          original_headline = "render #{new_call_node.source}"

          add_offense(node, message: format(MSG, suggestion: helper_headline, original: original_headline)) do |corrector|
            corrector.replace(outer_node, suggestion)
          end
        end

        private

        def inside_array_literal?(node)
          node.parent&.array_type?
        end

        def kit_namespace(const_node)
          segments = const_segments(const_node)
          return nil if segments.nil? || segments.length < 2

          KIT_MODULES.include?(segments.first) ? segments.first : nil
        end

        def const_segments(node)
          parts = []
          cur = node
          while cur&.const_type?
            parts.unshift(cur.short_name.to_s)
            cur = cur.children.first
          end
          parts
        end

        def helper_headline(new_call_node, const_node)
          args_source = call_args_source(new_call_node)
          prefix = const_node.source
          args_source.empty? ? "#{prefix}()" : "#{prefix}(#{args_source})"
        end

        def build_helper_call(new_call_node, const_node, outer_node, brace_block_node = nil)
          args_source = call_args_source(new_call_node)
          prefix = const_node.source
          helper = args_source.empty? ? "#{prefix}()" : "#{prefix}(#{args_source})"

          if outer_node.block_type?
            send_node = outer_node.send_node
            block_source = outer_node.source[send_node.source.length..]
            "#{helper}#{block_source}"
          elsif brace_block_node
            block_source = brace_block_node.source[new_call_node.source.length..]
            "#{helper}#{block_source}"
          else
            helper
          end
        end

        def call_args_source(new_call_node)
          return "" if new_call_node.arguments.empty?

          first = new_call_node.arguments.first
          last = new_call_node.arguments.last
          first_pos = first.source_range.begin_pos
          last_pos = last.source_range.end_pos
          new_call_node.source_range.source_buffer.source[first_pos...last_pos]
        end
      end
    end
  end
end
