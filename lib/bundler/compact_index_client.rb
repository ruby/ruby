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
    require_relative "compact_index_client/updater"

    attr_reader :directory

    def initialize(directory, fetcher)
      @directory = Pathname.new(directory)
      @updater = Updater.new(fetcher)
      @cache = Cache.new(@directory)
      @endpoints = Set.new
      @info_checksums_by_name = {}
      @parsed_checksums = false
      @mutex = Thread::Mutex.new
    end

    def execution_mode=(block)
      Bundler::CompactIndexClient.debug { "execution_mode=" }
      @endpoints = Set.new

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
      Bundler::CompactIndexClient.debug { "/names" }
      update("names", @cache.names_path, @cache.names_etag_path)
      @cache.names
    end

    def versions
      Bundler::CompactIndexClient.debug { "/versions" }
      update("versions", @cache.versions_path, @cache.versions_etag_path)
      versions, @info_checksums_by_name = @cache.versions
      versions
    end

    def dependencies(names)
      Bundler::CompactIndexClient.debug { "dependencies(#{names})" }
      execution_mode.call(names) do |name|
        update_info(name)
        @cache.dependencies(name).map {|d| d.unshift(name) }
      end.flatten(1)
    end

    def update_and_parse_checksums!
      Bundler::CompactIndexClient.debug { "update_and_parse_checksums!" }
      return @info_checksums_by_name if @parsed_checksums
      update("versions", @cache.versions_path, @cache.versions_etag_path)
      @info_checksums_by_name = @cache.checksums
      @parsed_checksums = true
    end

    private

    def update(remote_path, local_path, local_etag_path)
      Bundler::CompactIndexClient.debug { "update(#{local_path}, #{remote_path})" }
      unless synchronize { @endpoints.add?(remote_path) }
        Bundler::CompactIndexClient.debug { "already fetched #{remote_path}" }
        return
      end
      @updater.update(url(remote_path), local_path, local_etag_path)
    end

    def update_info(name)
      Bundler::CompactIndexClient.debug { "update_info(#{name})" }
      path = @cache.info_path(name)
      unless existing = @info_checksums_by_name[name]
        Bundler::CompactIndexClient.debug { "skipping updating info for #{name} since it is missing from versions" }
        return
      end
      checksum = SharedHelpers.checksum_for_file(path, :MD5)
      if checksum == existing
        Bundler::CompactIndexClient.debug { "skipping updating info for #{name} since the versions checksum matches the local checksum" }
        return
      end
      Bundler::CompactIndexClient.debug { "updating info for #{name} since the versions checksum #{existing} != the local checksum #{checksum}" }
      update("info/#{name}", path, @cache.info_etag_path(name))
    end

    def url(path)
      path
    end

    def synchronize
      @mutex.synchronize { yield }
    end
  end
end
