# frozen_string_literal: true

begin
  require "rubygems/vendored_tsort"
rescue LoadError
  require "tsort"
  # RubyGems older than 3.6 has no rubygems/vendored_tsort, but may have
  # already loaded its own API-compatible Gem::TSort through
  # rubygems/request_set, e.g. from Gem.activate_bin_path in binstubs.
  Gem::TSort = TSort unless defined?(Gem::TSort)
end
