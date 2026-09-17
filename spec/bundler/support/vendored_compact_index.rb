# frozen_string_literal: true

# Bundler specs load this code from the compact-index artifice, including
# inside spawned Bundler processes, so it must have no side effects beyond
# defining the VendoredCompactIndex constants; in particular it must not
# touch $LOAD_PATH or load any other spec setup code.
#
# The vendored copy under spec/support/vendor/compact_index/ is rubygems.org's
# `lib/compact_index/`, renamed to the VendoredCompactIndex namespace so it can
# never collide with the V1-only CompactIndex constants that
# rubygems-generate_index loads for Gem::Indexer. Refresh it with
# `rake vendor:compact_index`.
#
require_relative "vendor/compact_index/lib/compact_index" unless defined?(VendoredCompactIndex)
