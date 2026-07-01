# frozen_string_literal: true

module Views
  # The drawer sidebar. Provided by docs-kit (Docs::Sidebar), driven by the nav
  # configured in config/initializers/docs_kit.rb (Demo + Doc registries). This
  # subclass keeps the historical `Views::Sidebar` name.
  class Sidebar < ::Docs::Sidebar
  end
end
