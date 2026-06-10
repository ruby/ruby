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

  # info returns an Array of INFO Arrays. Each INFO Array has the following indices:
  INFO_NAME = 0
  INFO_VERSION = 1
  INFO_PLATFORM = 2
  INFO_DEPS = 3
  INFO_REQS = 4

  def self.debug
    return unless ENV["DEBUG_COMPACT_INDEX"]
    DEBUG_MUTEX.synchronize { warn("[#{self}] #{yield}") }
  end

  class Error < StandardError; end

  require_relative "compact_index_client/cache"
  require_relative "compact_index_client/cache_file"
  require_relative "compact_index_client/parser"
  require_relative "compact_index_client/updater"

  # The client is instantiated with:
  # - `directory`: the root directory where the cache files are stored.
  # - `fetcher`: (optional) an object that responds to #call(uri_path, headers)
  #   and returns a Gem::Net::HTTP response. When the fetcher is not provided,
  #   the client only reads cached files from disk.
  def initialize(directory, fetcher = nil)
    @cache = Cache.new(directory, fetcher)
    @parser = Parser.new(@cache)
  end

  def names
    Gem::CompactIndexClient.debug { "names" }
    @parser.names
  end

  def versions
    Gem::CompactIndexClient.debug { "versions" }
    @parser.versions
  end

  def dependencies(names)
    Gem::CompactIndexClient.debug { "dependencies(#{names})" }
    names.map {|name| info(name) }
  end

  def info(name)
    Gem::CompactIndexClient.debug { "info(#{name})" }
    @parser.info(name)
  end

  def latest_version(name)
    Gem::CompactIndexClient.debug { "latest_version(#{name})" }
    @parser.info(name).map {|d| Gem::Version.new(d[INFO_VERSION]) }.max
  end

  def available?
    Gem::CompactIndexClient.debug { "available?" }
    @parser.available?
  end

  def reset!
    Gem::CompactIndexClient.debug { "reset!" }
    @cache.reset!
  end
end
