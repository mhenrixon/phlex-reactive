# frozen_string_literal: true

class DemosController < ApplicationController
  def show
    demo = Demo.from_slug(params[:demo])
    return head :not_found unless demo

    render_page Views::Demos::Show.new(demo: demo)
  end
end
