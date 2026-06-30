# frozen_string_literal: true

class DocsController < ApplicationController
  def show
    doc = Doc.from_slug(params[:doc])
    view = doc&.view_class
    return head :not_found unless view

    render_page view.new
  end
end
