# frozen_string_literal: true

require "system_helper"

# Issue #11: a reactive component wired with form(**on(:save, event: "submit"))
# must intercept the submit and run the reactive action, NOT navigate.
#
# This is an end-to-end SMOKE test (submit-triggered action works, page stays
# put). It does NOT isolate the preventDefault-timing race itself: the Turbo-8
# submit race that surfaces the bug isn't reproducible in the minimal dummy app
# (a native submit here is suppressed regardless of the fix). The actual
# regression guard for the synchronous-preventDefault contract is the bun unit
# test at spec/javascript/reactive_controller.test.js, which fails on the
# pre-fix (deferred) code.
RSpec.describe "Reactive form submit (issue #11)", type: :system do
  it "runs a submit-triggered reactive action without navigating away" do
    todo = Todo.create!(title: "before")
    visit "/form_submit/#{todo.id}"

    find("[data-testid='title']").set("after submit")
    find("[data-testid='save']").click

    # The reactive re-render lands in place (waiting matcher = async barrier).
    expect(page).to have_css("[data-testid='current']", text: "after submit")
    # We never navigated to the form's action: the nav-probe sentinel is absent.
    expect(page).to have_no_css("[data-testid='nav-probe']")
    expect(todo.reload.title).to eq("after submit")
  end
end
