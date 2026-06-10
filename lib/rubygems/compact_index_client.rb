# frozen_string_literal: true

##
# The CompactIndexClient fetches and parses the compact index files
# (names, versions and info/[gem]) served by a gem server, keeping a
# local cache so subsequent fetches only transfer what changed.
#
# This is an independent RubyGems port of Bundler::CompactIndexClient.
# Both implementations are intentionally kept separate so that changes
# on either side cannot affect the other; this one only depends on
# RubyGems itself.

class Gem::CompactIndexClient
  SUPPORTED_DIGESTS = { "sha-256" => :SHA256 }.freeze
  DEBUG_MUTEX = Thread::Mutex.new

  def self.debug
    return unless ENV["DEBUG_COMPACT_INDEX"]
    DEBUG_MUTEX.synchronize { warn("[#{self}] #{yield}") }
  end

  class Error < StandardError; end

  require_relative "compact_index_client/cache"
  require_relative "compact_index_client/cache_file"
  require_relative "compact_index_client/parser"
  require_relative "compact_index_client/updater"
end
