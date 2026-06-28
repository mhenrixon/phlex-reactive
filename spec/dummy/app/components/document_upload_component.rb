# frozen_string_literal: true

# Issue #34: a reactive component that accepts a FILE in its action. When the
# reactive root contains a populated <input type="file">, the client sends the
# action as multipart FormData (not JSON) and the endpoint coerces the declared
# `:file` param to the ActionDispatch::Http::UploadedFile, passed through
# untouched. The action attaches it to the record via ActiveStorage — the rest
# of the reactive flow (token threading, re-render/morph) is identical.
class DocumentUploadComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  reactive_record :document

  # Single-file path (has_one_attached). A caption rides alongside as a scalar
  # field to prove multipart carries scalar params + the file together.
  action :upload, params: {file: :file, caption: :string}
  # Multiple-file path (has_many_attached): [:file] coerces an array of uploads.
  action :upload_pages, params: {pages: [:file]}

  def initialize(document:)
    @document = document
  end

  def id = dom_id(@document)

  def upload(file: nil, caption: nil)
    @document.file.attach(file) if file
    @document.update!(title: caption) if caption.present?
  end

  def upload_pages(pages: nil)
    @document.pages.attach(pages) if pages.present?
  end

  def view_template
    div(**mix(reactive_attrs, id:, data: {testid: "document"})) do
      span(data: {testid: "title"}) { @document.title }
      span(data: {testid: "filename"}) { @document.file.attached? ? @document.file.filename.to_s : "" }
      span(data: {testid: "pages-count"}) { @document.pages.count.to_s }

      form(**on(:upload, event: "submit")) do
        input(type: "file", name: "file", data: {testid: "file"})
        input(name: "caption", data: {testid: "caption"})
        button(type: "submit", data: {testid: "save"}) { "Upload" }
      end
    end
  end
end
