# frozen_string_literal: true

# Base for the docs' own reactive CHROME components (the context switcher, the
# reactive modal) — the parts of the docs UI that are themselves reactive and
# also render docs-kit chrome (DocsUI::Code, DocsUI::Icon). It bundles the
# reactive mixins + the DocsUI kit so those components can use the short kit form.
#
# The user-facing DEMO components (CounterComponent, TodoListComponent, ...) do
# NOT inherit from this — they deliberately stay `< Phlex::HTML` with explicit
# `include Phlex::Reactive::*`, because they double as copy-paste examples of how
# a host app writes a reactive component.
#
# Reparenting is token-safe: the signed identity carries `klass.name` (the class
# name string), not the ancestry, so ContextSwitcherComponent stays
# "ContextSwitcherComponent" in the token.
class ReactiveBase < Phlex::HTML
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component
  include DocsUI
end
