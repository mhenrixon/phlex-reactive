# frozen_string_literal: true

require "system_helper"

# Issue #34: attaching a file is a first-class reactive action. The component's
# form carries a <input type="file">; when the user submits, the reactive
# controller detects the chosen file and sends the action as multipart FormData
# (not JSON), so the file reaches the action and ActiveStorage attaches it. The
# re-render lands in place — no full-page reload, no bespoke upload controller.
#
# This is the end-to-end proof of the whole multipart path under a REAL browser
# and a REAL server (Puma default; Falcon via CAPYBARA_SERVER=falcon). The wire
# encoding (FormData vs JSON) is unit-tested in spec/javascript; the server
# coercion in spec/requests — this proves they meet in the browser.
RSpec.describe "Reactive file upload (issue #34)", type: :system do
  it "attaches an uploaded file via a reactive action without a full-page reload" do
    document = Document.create!(title: "untitled")
    visit "/document_upload/#{document.id}"
    page.execute_script("window.__noReload = 'alive'")

    # No attachment yet.
    expect(page).to have_css("[data-testid='filename']", text: "")

    attach_file("file", Rails.root.join("..", "fixtures", "files", "receipt.txt").to_s, make_visible: true)
    fill_in("caption", with: "My receipt")
    find("[data-testid='save']").click

    # The reactive re-render lands in place: the filename + caption appear
    # (waiting matchers = the async morph barrier), proving the multipart action
    # ran and the attachment + scalar param both landed.
    expect(page).to have_css("[data-testid='filename']", text: "receipt.txt")
    expect(page).to have_css("[data-testid='title']", text: "My receipt")

    # The attachment actually persisted server-side.
    expect(document.reload.file).to be_attached
    expect(document.file.filename.to_s).to eq("receipt.txt")

    # No full-page reload happened — the action was a reactive round trip, not a
    # native multipart form POST that navigates.
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  # Issue #231: Rails-bracketed field names (blog_post[summary] + blog_post[image])
  # on the multipart path. The old client wrapped the names verbatim
  # (params[blog_post[summary]]), which Rack mangled — the scalar corrupted into
  # a stringified {"]" => …} hash written to the record with a 200, and the file
  # silently dropped. It ONLY fires with a populated file input (the JSON path
  # expands the same names server-side), which is exactly why flat-named upload
  # forms above never caught it. This drives the real browser build end-to-end.
  it "carries bracketed field names cleanly alongside a file (issue #231)" do
    document = Document.create!(title: "untitled")
    visit "/document_upload/#{document.id}"

    fill_in("blog_post[summary]", with: "This is cool")
    attach_file("blog_post[image]", Rails.root.join("..", "fixtures", "files", "receipt.txt").to_s,
      make_visible: true)
    find("[data-testid='save-post']").click

    # The waiting matcher is the async-morph barrier: the CLEAN summary lands —
    # never the corrupted {"]"=>"This is cool"} stringification.
    expect(page).to have_css("[data-testid='title']", text: "This is cool")
    expect(page).to have_css("[data-testid='filename']", text: "receipt.txt")

    expect(document.reload.title).to eq("This is cool")
    expect(document.file).to be_attached
  end
end
