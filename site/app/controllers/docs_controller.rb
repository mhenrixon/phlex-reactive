# frozen_string_literal: true

class DocsController < ApplicationController
  def show
    doc = Doc.from_slug(params[:doc])
    return head :not_found unless doc

    render_page Views::Docs::Show.new(doc: doc)
  end
end
