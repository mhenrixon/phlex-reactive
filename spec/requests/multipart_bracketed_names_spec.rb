# frozen_string_literal: true

require "rails_helper"

# Issue #231: a Rails-conventional BRACKETED field name (blog_post[summary],
# blog_post[image]) on the multipart path. The old client wrapped the collected
# name verbatim — params[blog_post[summary]] — which Rack cannot parse as
# nesting: the scalar arrived as {"blog_post[summary" => {"]" => value}} (data
# corruption stringified into the record with a 200) and the file never reached
# its schema key (silent drop).
#
# The fix is client-side: #buildFormData bracket-expands the field NAME into
# params[blog_post][summary] / params[blog_post][image] — the same shape a
# native Rails form posts and the JSON path already coerces via
# expand_bracket_keys. These specs post that FIXED wire shape end-to-end
# (Rack::Test flattens the nested Hash into exactly those bracketed field
# names) and assert the server contract the client fix relies on: a nested
# schema with a :file leaf coerces the scalar AND the file together.
RSpec.describe "Multipart bracketed field names (issue #231)", type: :request do
  def post_multipart(klass, payload:, act:, params: {})
    post "/reactive/actions",
      params: { token: token_for(klass, payload), act:, params: },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  let!(:document) { Document.create!(title: "untitled") }
  let(:payload) { { "gid" => document.to_gid.to_s } }
  let(:upload) { fixture_file_upload("receipt.txt", "text/plain") }

  it "coerces a scalar riding under a bracketed root next to a file (the corruption case)" do
    post_multipart(DocumentUploadComponent, payload:, act: "save_post",
      params: { blog_post: { summary: "<p>This is cool</p>", image: upload } })

    expect(response).to have_http_status(:ok)
    # The clean string — never the {"]" => "…"} hash the verbatim wrap produced.
    expect(document.reload.title).to eq("<p>This is cool</p>")
    expect(document.file).to be_attached
    expect(document.file.filename.to_s).to eq("receipt.txt")
  end

  it "coerces a :file under a bracketed name alone (the silent-drop case)" do
    post_multipart(DocumentUploadComponent, payload:, act: "save_post",
      params: { blog_post: { image: upload } })

    expect(response).to have_http_status(:ok)
    expect(document.reload.file).to be_attached
    expect(document.title).to eq("untitled") # blank summary → keyword guard, no write
  end
end
