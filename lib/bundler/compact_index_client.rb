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

    def execution_mode=(block)
      Bundler::CompactIndexClient.debug { "execution_mode=" }
      @cache.reset!
      @execution_mode = block
    end

    # @return [Lambda] A lambda that takes an array of inputs and a block, and
    #         maps the inputs with the block in parallel.
    #
    def execution_mode
      @execution_mode || sequentially
    end

    def sequential_execution_mode!
      self.execution_mode = sequentially
    end

    def sequentially
      @sequentially ||= lambda do |inputs, &blk|
        inputs.map(&blk)
      end
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
      execution_mode.call(names) {|name| @parser.info(name) }.flatten(1)
    end

    def latest_version(name)
      Bundler::CompactIndexClient.debug { "latest_version(#{name})" }
      @parser.info(name).map {|d| Gem::Version.new(d[1]) }.max
    end

    def available?
      Bundler::CompactIndexClient.debug { "available?" }
      @parser.available?
    end
  end
end
