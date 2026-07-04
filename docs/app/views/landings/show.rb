# frozen_string_literal: true

module Views
  module Landings
    class Show < Phlex::HTML
      include Phlex::Rails::Helpers::Routes

      FEATURES = [
        ['shield-check', 'Signed identity, not state',
         'The DOM carries a MessageVerifier-signed { c, gid } — never raw state. Tampering fails verification.'],
        ['lock', 'Default-deny actions',
         'Only methods you declare with action :name run. Undeclared → 403. You authorize inside the action.'],
        ['refresh-cw', 'One re-render unit',
         'A click, a form change, and a background broadcast all resolve to “render this component into that id.”'],
        ['database', 'pgbus-optional transport',
         'Broadcasts route through Turbo Streams — Action Cable OR pgbus over Postgres SSE. No hard dependency.']
      ].freeze

      def initialize(demos:)
        @demos = demos
      end

      def view_template
        DocsUI::Shell(
          title: nil,
          description: 'Reactive Phlex components for Rails — Livewire-style actions and ' \
                       'live cross-tab updates, no bespoke JS. Signed identity, default-deny ' \
                       'actions, pgbus-optional transport.'
        ) do
          hero
          feature_grid
          demos_section
          docs_section
        end
      end

      private

      def hero
        section(class: 'not-prose mb-14') do
          div(class: 'flex items-center gap-3 mb-6') do
            brand_mark
            span(class: 'text-sm font-semibold tracking-wide opacity-70') { 'phlex-reactive' }
          end
          h1(class: 'text-4xl sm:text-5xl font-extrabold tracking-tight mb-4 leading-tight') do
            plain 'Reactive '
            a(href: 'https://www.phlex.fun',
              class: 'bg-gradient-to-r from-primary to-accent bg-clip-text text-transparent') { 'Phlex' }
            plain ' components for Rails'
          end
          p(class: 'text-lg sm:text-xl opacity-80 max-w-2xl mb-7') do
            plain 'Livewire-style actions and live cross-tab updates — '
            plain 'without writing Stimulus controllers or hand-picking Turbo Stream targets. '
            strong { 'Every demo below runs live.' }
          end
          div(class: 'flex flex-wrap gap-3 mb-10') do
            a(href: doc_path('installation'),
              class: 'btn btn-primary', data: { testid: 'cta-get-started' }) { 'Get started' }
            a(href: doc_path('architecture'), class: 'btn btn-ghost') { 'How it works' }
            a(href: 'https://github.com/mhenrixon/phlex-reactive',
              class: 'btn btn-ghost', target: '_blank', rel: 'noopener') { 'GitHub ↗' }
          end
          render Components::Diagrams::MentalModel.new
        end
      end

      def brand_mark
        div(class: 'w-9 h-9 rounded-lg bg-base-200 grid place-items-center') do
          div(class: 'w-5 h-5 rotate-45 rounded-sm bg-gradient-to-br from-primary to-accent')
        end
      end

      def feature_grid
        section(class: 'not-prose mb-16') do
          div(class: 'grid gap-4 sm:grid-cols-2') do
            FEATURES.each { feature_card(it) }
          end
        end
      end

      def feature_card((icon, title, body))
        div(class: 'card bg-base-200/60 border border-base-300 p-5') do
          div(class: 'flex items-start gap-3') do
            div(class: 'text-primary mt-0.5') { DocsUI::Icon(icon) }
            div do
              h3(class: 'font-semibold mb-1') { title }
              p(class: 'text-sm opacity-70') { body }
            end
          end
        end
      end

      def demos_section
        section(class: 'not-prose mb-14') do
          h2(class: 'text-sm uppercase tracking-wide opacity-60 mb-4') { 'Live demos' }
          div(class: 'grid gap-4 sm:grid-cols-2') do
            @demos.each { demo_card(it) }
          end
        end
      end

      def docs_section
        section(class: 'not-prose') do
          h2(class: 'text-sm uppercase tracking-wide opacity-60 mb-4') { 'Documentation' }
          Doc.grouped.each do |group, docs|
            written = docs.select(&:view_class)
            next if written.empty?

            h3(class: 'text-xs font-semibold uppercase tracking-wider opacity-40 mt-5 mb-2') { group }
            div(class: 'grid gap-2 sm:grid-cols-2') do
              written.each { doc_link(it) }
            end
          end
        end
      end

      def demo_card(demo)
        a(href: demo_path(demo.slug),
          class: 'card bg-base-200 hover:bg-base-300 transition-colors p-5 block group',
          data: { testid: "demo-card-#{demo.slug}" }) do
          div(class: 'flex items-center justify-between mb-1') do
            h3(class: 'text-xl font-semibold') { demo.title }
            span(class: 'opacity-0 group-hover:opacity-60 transition-opacity text-sm') { '→' }
          end
          p(class: 'opacity-70 text-sm') { demo.blurb }
        end
      end

      def doc_link(doc)
        a(href: doc_path(doc.slug),
          class: 'link link-hover text-sm py-1 flex items-center gap-2',
          data: { testid: "doc-link-#{doc.slug}" }) do
          span(class: 'text-primary/50') { '›' }
          plain doc.title
        end
      end
    end
  end
end
