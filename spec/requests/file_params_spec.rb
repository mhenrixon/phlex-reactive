# frozen_string_literal: true

require "rails_helper"

# Issue #34: a reactive action can receive a FILE. The client sends the action
# as multipart FormData (token + act + scalar params as fields, files appended)
# instead of JSON; the endpoint coerces the declared `:file` param to the
# ActionDispatch::Http::UploadedFile, passed through untouched. A non-file value
# sent to a `:file` param is DROPPED (consistent with #16 coercion rules), so the
# method's keyword default applies — never a fabricated/coerced file.
RSpec.describe "Reactive file/multipart params", type: :request do
  def token_for(klass, payload)
    Phlex::Reactive.sign(payload.merge("c" => klass.name))
  end

  # A multipart POST, exactly as the client's FormData path produces it: token
  # and act are flat fields, params are bracketed (params[caption], params[file]).
  def post_multipart(klass, payload:, act:, params: {})
    post "/reactive/actions",
      params: {token: token_for(klass, payload), act:, params:},
      headers: {"Accept" => "text/vnd.turbo-stream.html"}
  end

  let!(:document) { Document.create!(title: "untitled") }
  let(:payload) { {"gid" => document.to_gid.to_s} }
  let(:upload) { fixture_file_upload("receipt.txt", "text/plain") }

  describe "single file (:file)" do
    it "coerces the upload to an UploadedFile and the action attaches it" do
      post_multipart(DocumentUploadComponent, payload:, act: "upload",
        params: {file: upload, caption: "My receipt"})

      expect(response).to have_http_status(:ok)
      expect(document.reload.file).to be_attached
      expect(document.file.filename.to_s).to eq("receipt.txt")
      expect(document.title).to eq("My receipt") # scalar param rode alongside
    end

    it "drops a non-file value sent to a :file param (no fake file reaches the action)" do
      # A forged/malformed payload puts a plain string where a file is declared.
      post_multipart(DocumentUploadComponent, payload:, act: "upload",
        params: {file: "not-a-file", caption: "still here"})

      expect(response).to have_http_status(:ok)
      expect(document.reload.file).not_to be_attached # the :file param was dropped
      expect(document.title).to eq("still here")      # the scalar still coerced
    end

    it "passes through with no file when the input is empty (keyword default applies)" do
      post_multipart(DocumentUploadComponent, payload:, act: "upload",
        params: {caption: "no file this time"})

      expect(response).to have_http_status(:ok)
      expect(document.reload.file).not_to be_attached
      expect(document.title).to eq("no file this time")
    end
  end

  describe "multiple files ([:file])" do
    it "coerces an array of uploads and attaches them all" do
      pages = [fixture_file_upload("page1.txt", "text/plain"),
        fixture_file_upload("page2.txt", "text/plain")]

      post_multipart(DocumentUploadComponent, payload:, act: "upload_pages",
        params: {pages:})

      expect(response).to have_http_status(:ok)
      expect(document.reload.pages.count).to eq(2)
      expect(document.pages.map { |p| p.filename.to_s }).to contain_exactly("page1.txt", "page2.txt")
    end
  end

  describe "JSON path is unaffected (back-compat)" do
    it "still serves a JSON-bodied action with no file param" do
      post "/reactive/actions",
        params: {token: token_for(DocumentUploadComponent, payload), act: "upload", params: {caption: "json only"}}.to_json,
        headers: {"Content-Type" => "application/json", "Accept" => "text/vnd.turbo-stream.html"}

      expect(response).to have_http_status(:ok)
      expect(document.reload.title).to eq("json only")
      expect(document.file).not_to be_attached
    end
  end
end
