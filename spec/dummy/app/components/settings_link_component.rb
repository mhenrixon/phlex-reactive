# frozen_string_literal: true

# Fixture for issue #232: a reply-rendered component that emits an ABSOLUTE URL
# (`counter_url` — the same url_options path image_tag takes for an Active
# Storage attachment). On a multi-host app the reply must carry the REQUESTING
# host, not the process default; a broadcast of the same component must keep
# the process default (subscribers can be on other hosts).
class SettingsLinkComponent < ApplicationComponent
  include Phlex::Reactive::Component
  include Phlex::Rails::Helpers::Routes

  reactive_state :saved

  action :save
  action :save_and_broadcast

  def initialize(saved: false)
    @saved = saved
  end

  def id = "settings-link"

  def save
    @saved = true
  end

  # Broadcast the SAME component while handling the actor's request — the
  # broadcast render must NOT inherit the actor's url_options (issue #232).
  def save_and_broadcast
    @saved = true
    self.class.broadcast_to("settings", replace: self.class.new(saved: true))
  end

  def view_template
    div(id:, **reactive_attrs) do
      a(href: counter_url, data: { testid: "abs-link" }) { "counter" }
      span(data: { testid: "saved" }) { @saved.to_s }
      button(**mix(on(:save), data: { testid: "save" })) { "save" }
    end
  end
end
