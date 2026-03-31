# frozen_string_literal: true

require_relative "shared_helpers"
Bundler::SharedHelpers.feature_removed! "Bundler no longer integrates with " \
  "Capistrano, but Capistrano provides its own integration with " \
  "Bundler via the capistrano-bundler gem. Use it instead."
