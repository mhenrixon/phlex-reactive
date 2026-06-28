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
  # Issue #39: a :file param alongside an explicit NESTED-hash param. The nested
  # `meta` used to be dropped on the multipart path (the exact combination the
  # issue flagged); it must now survive next to the file.
  action :upload_with_meta, params: {file: :file, meta: {tag: :string, year: :integer}}

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

  # Attach the file AND fold the nested meta into the title, so a spec can assert
  # the nested-hash param rode alongside the file through the multipart path.
  def upload_with_meta(file: nil, meta: nil)
    @document.file.attach(file) if file
    @document.update!(title: "#{meta[:tag]} #{meta[:year]}") if meta
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
