# frozen_string_literal: true

require "pathname"
require "set"

module Bundler
  class CompactIndexClient
    # NOTE: MD5 is here not because we expect a server to respond with it, but
    # because we use it to generate the etag on first request during the upgrade
    # to the compact index client that uses opaque etags saved to files.
    # Remove once 2.5.0 has been out for a while.
    SUPPORTED_DIGESTS = { "sha-256" => :SHA256, "md5" => :MD5 }.freeze
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

    def initialize(directory, fetcher = nil)
      @cache = Cache.new(directory, fetcher)
      @parser = Parser.new(@cache)
    end

    def names
      Bundler::CompactIndexClient.debug { "names" }
      @parser.names
    end

    def versions
      Bundler::CompactIndexClient.debug { "versions" }
      @parser.versions
    end

    def dependencies(names)
      Bundler::CompactIndexClient.debug { "dependencies(#{names})" }
      names.map {|name| info(name) }
    end

    def info(name)
      Bundler::CompactIndexClient.debug { "info(#{names})" }
      @parser.info(name)
    end

    def latest_version(name)
      Bundler::CompactIndexClient.debug { "latest_version(#{name})" }
      @parser.info(name).map {|d| Gem::Version.new(d[INFO_VERSION]) }.max
    end

    def available?
      Bundler::CompactIndexClient.debug { "available?" }
      @parser.available?
    end

    def reset!
      Bundler::CompactIndexClient.debug { "reset!" }
      @cache.reset!
    end
  end
end
