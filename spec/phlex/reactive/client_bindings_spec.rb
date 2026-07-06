# frozen_string_literal: true

require "spec_helper"
require "phlex"

# Issue #180 Phase A: ClientBindings — the blessed CLIENT-ONLY include. A view
# that only shows/hides, filters, or computes client-side (no server actions, no
# token) includes this instead of the full Component. It does NOT pull in
# Streamable (so it never clobbers an app's own replace/to_stream_* concern) or
# the token machinery (a tokenless reactive_root, no #id requirement, invisible
# to phlex_reactive:doctor).
RSpec.describe Phlex::Reactive::ClientBindings do
  let(:client_klass) do
    Class.new(Phlex::HTML) do
      include Phlex::Reactive::ClientBindings

      def self.name = "ClientOnlyThing"

      reactive_scope :form

      def reactive_values = { director: true }

      def view_template
        div(**reactive_root) do
          div(**reactive_show(if: { director: true })) { "director fields" }
        end
      end
    end
  end

  it "emits a TOKEN-LESS reactive root (controller, but no token)" do
    attrs = client_klass.new.send(:reactive_root)
    expect(attrs[:data][:controller]).to eq("reactive")
    expect(attrs[:data]).not_to have_key(:reactive_token_value)
  end

  it "carries the declared scope on the root" do
    expect(client_klass.new.send(:reactive_root)[:data][:reactive_scope]).to eq("form")
  end

  it "does NOT require an #id (no Streamable default that raises)" do
    # A client-only root has no record and no #id; reactive_root must not raise.
    expect { client_klass.new.send(:reactive_root) }.not_to raise_error
  end

  it "provides the conditions-language show helper with first-paint hidden:" do
    attrs = client_klass.new.send(:reactive_show, if: { director: true })
    expect(attrs[:hidden]).to be(false) # reactive_values says director true → visible
    expect(attrs[:data]).to have_key(:reactive_show)
  end

  it "renders end to end without a token" do
    html = client_klass.new.call
    expect(html).to include('data-controller="reactive"')
    expect(html).to include("data-reactive-show=")
    expect(html).not_to include("reactive-token-value")
  end

  it "does NOT include Streamable (no replace/to_stream_* to clobber an app concern)" do
    expect(client_klass.include?(Phlex::Reactive::Streamable)).to be(false)
    expect(client_klass.new).not_to respond_to(:to_stream_replace)
  end

  it "does NOT enroll in the Streamable component registry (doctor never flags it)" do
    client_klass # force definition
    expect(Phlex::Reactive::Streamable.registered_classes).not_to include(client_klass)
  end

  it "still exposes on_client and js for zero-round-trip ops" do
    instance = client_klass.new
    expect(instance.send(:js)).to be_a(Phlex::Reactive::JS)
    attrs = instance.send(:on_client, :click, instance.send(:js).hide("#x"))
    expect(attrs[:data][:action]).to include("reactive#runOps")
  end

  it "is also mixed into a full Component (one implementation, via the Concern chain)" do
    full = Class.new(Phlex::HTML) do
      include Phlex::Reactive::Component

      def self.name = "FullComponentThing"
    end
    expect(full.ancestors).to include(described_class)
  end
end
