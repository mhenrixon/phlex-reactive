# frozen_string_literal: true

# Micro-bench: server-side param coercion (ActionsController#coerce_params). It
# runs on every action that declares a param schema, recursing through nested
# hashes/arrays and expanding Rails bracket keys. This isolates the coercion of
# a realistic nested payload (a Rails Form(model:) with an array of nested
# attributes) so allocation/throughput regressions in the recursion show up.
#
#   ruby benchmark/micro/coerce_params.rb

require_relative "../support/boot"

controller = Phlex::Reactive::ActionsController.new

schema = {
  date: :string,
  bank_account_ids: [:integer],
  invoice_items_attributes: [{id: :integer, quantity: :float, price: :float, _destroy: :boolean}]
}

# A flat, bracketed payload (what the client's #collectFields posts for a
# Rails-style nested form) as an ActionController::Parameters, the real input.
raw = ActionController::Parameters.new(
  "date" => "2026-01-02",
  "bank_account_ids[]" => %w[1 2 3],
  "invoice_items_attributes[0][id]" => "10",
  "invoice_items_attributes[0][quantity]" => "2.5",
  "invoice_items_attributes[0][price]" => "9.99",
  "invoice_items_attributes[0][_destroy]" => "false",
  "invoice_items_attributes[1][id]" => "11",
  "invoice_items_attributes[1][quantity]" => "1.0",
  "invoice_items_attributes[1][price]" => "4.50",
  "invoice_items_attributes[1][_destroy]" => "true"
)

# coerce_params reads params.fetch(:params, {}); set it on the controller.
controller.params = ActionController::Parameters.new(params: raw)
run = -> { controller.send(:coerce_params, schema) }

BenchSupport.header("coerce_params: nested array-of-hash (Rails bracket form)")
BenchSupport.ips { |x| x.report("coerce_params") { run.call } }

BenchSupport.header("coerce_params allocations (per call)")
BenchSupport.allocations("coerce_params") { run.call }
