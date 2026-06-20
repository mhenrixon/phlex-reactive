# frozen_string_literal: true

# Record-backed reactive components sign a record's GlobalID; GlobalID needs an
# app name to build/parse GIDs.
Rails.application.config.global_id.app = "dummy"
