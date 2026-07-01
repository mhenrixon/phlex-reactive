# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # Render a Phlex page view. Docs::Shell IS the full HTML document (its own
  # <html>/<head>/<body> + the daisyUI drawer shell), so it must NOT be wrapped
  # in the Rails ERB application layout — `layout: false` prevents the double
  # <html> nesting (and the scaffold layout's `main.container mt-28 flex` that
  # was offsetting and mis-columning the page). phlex-rails still renders through
  # a real view context, so the reactive token signer, dom_id, csrf, and url
  # helpers all work inside the components on the page.
  def render_page(view)
    render view, layout: false
  end
end
