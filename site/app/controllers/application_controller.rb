# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # Render a Phlex page view. phlex-rails renders it through a real Rails view
  # context, so the reactive token signer, dom_id, csrf, and url helpers all work
  # inside the reactive components on the page.
  def render_page(view)
    render view
  end
end
