# frozen_string_literal: true

module Views
  module Docs
    # A typographic wrapper for hand-authored doc prose. Gives consistent reading
    # rhythm without depending on the Tailwind typography plugin (not bundled in
    # the standalone CLI): child elements are styled via Tailwind's arbitrary-
    # variant child selectors. Authoring a doc is just writing p/ul/h3/code inside.
    #
    #   render Views::Docs::Prose.new do
    #     p { "A component owns a stable DOM id." }
    #     ul { li { "…" } }
    #   end
    class Prose < Phlex::HTML
      CLASSES = [
        'max-w-none text-base-content/80 leading-relaxed',
        '[&_p]:my-4',
        '[&_a]:text-primary [&_a]:underline [&_a:hover]:no-underline',
        '[&_strong]:text-base-content [&_strong]:font-semibold',
        '[&_h3]:mt-8 [&_h3]:mb-3 [&_h3]:text-lg [&_h3]:font-semibold [&_h3]:text-base-content',
        '[&_ul]:my-4 [&_ul]:list-disc [&_ul]:pl-6 [&_ul>li]:my-1',
        '[&_ol]:my-4 [&_ol]:list-decimal [&_ol]:pl-6 [&_ol>li]:my-1',
        '[&_code]:rounded [&_code]:bg-base-300 [&_code]:px-1.5 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-sm',
        '[&_:where(pre)_code]:bg-transparent [&_:where(pre)_code]:p-0'
      ].join(' ').freeze

      def view_template(&)
        div(class: CLASSES, &)
      end
    end
  end
end
