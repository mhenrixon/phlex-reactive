# frozen_string_literal: true

module Views
  # Renders a synced lucide icon as inline SVG. Thin Phlex wrapper over IconHelper.
  #   render Views::Icon.new("search", class: "size-4")
  class Icon < Phlex::HTML
    include IconHelper

    def initialize(name, **attributes)
      @name = name
      @attributes = attributes
    end

    def view_template
      raw(safe(_lucide(@name, **@attributes))) # rubocop:disable Rails/OutputSafety
    end
  end
end
