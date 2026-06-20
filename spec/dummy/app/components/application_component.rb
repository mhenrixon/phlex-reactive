# frozen_string_literal: true

# Base component for the dummy app, mirroring how a real Phlex+Rails app sets
# one up: include the Rails helpers reactive components rely on (dom_id, etc.).
class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::DOMID
end
