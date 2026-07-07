# frozen_string_literal: true

# Issue #187: prepare the Postgres test DB for the pgbus transport cell. Boots
# the dummy under TRANSPORT=pgbus (Postgres), loads the app schema, and installs
# pgbus's vendored PGMQ schema (idempotent — no CREATE EXTENSION, so it runs on a
# plain postgres:18). Run via `rake pgbus:prepare_test_db` (CI + spec:system_matrix).
require_relative "../dummy/config/environment"
require "pgbus/pgmq_schema"

ActiveRecord::Schema.verbose = false
load Rails.root.join("db/schema.rb")

conn = ActiveRecord::Base.connection
pgmq_present = conn
  .select_value("SELECT count(*) FROM information_schema.schemata WHERE schema_name = #{conn.quote("pgmq")}")
  .to_i
  .positive?
conn.execute(Pgbus::PgmqSchema.install_sql) unless pgmq_present

# This is a rake-invoked setup SCRIPT, not an example — the status line is for
# the CI log, not a spec expectation.
puts "pgbus test DB ready (app schema + PGMQ)" # rubocop:disable RSpec/Output
