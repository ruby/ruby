# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname" unless defined?(Pathname)
require "set"

class Gem::CompactIndexClient
  # Calls the Updater to update the cached files on disk, reads the
  # cached files and returns their contents.
  class Cache
    attr_reader :directory

    def initialize(directory, fetcher = nil)
      @directory = Pathname.new(directory).expand_path
      @updater = Updater.new(fetcher) if fetcher
      @mutex = Thread::Mutex.new
      @endpoints = Set.new

      @info_root = mkdir("info")
      @special_characters_info_root = mkdir("info-special-characters")
      @info_etag_root = mkdir("info-etags")
    end

    def names
      fetch("names", names_path, names_etag_path)
    end

    def versions
      fetch("versions", versions_path, versions_etag_path)
    end

    def info(name, remote_checksum = nil)
      path = info_path(name)

      if remote_checksum && remote_checksum != checksum_for_file(path)
        fetch("info/#{name}", path, info_etag_path(name))
      else
        Gem::CompactIndexClient.debug { "update skipped info/#{name} (#{remote_checksum ? "versions index checksum matches local" : "versions index checksum is nil"})" }
        read(path)
      end
    end

    # Fetch a single gem's info file without consulting the versions
    # index, refreshing the cached file with a conditional request.
    def fetch_info(name)
      fetch("info/#{name}", info_path(name), info_etag_path(name))
    end

    def reset!
      @mutex.synchronize { @endpoints.clear }
    end

    private

    def names_path = directory.join("names")
    def names_etag_path = directory.join("names.etag")
    def versions_path = directory.join("versions")
    def versions_etag_path = directory.join("versions.etag")

    def info_path(name)
      name = name.to_s
      if /[^a-z0-9_-]/.match?(name)
        name += "-#{Digest::MD5.hexdigest(name).downcase}"
        @special_characters_info_root.join(name)
      else
        @info_root.join(name)
      end
    end

    def info_etag_path(name)
      name = name.to_s
      @info_etag_root.join("#{name}-#{Digest::MD5.hexdigest(name).downcase}")
    end

    def checksum_for_file(path)
      return unless path.file?
      Digest::MD5.file(path).hexdigest
    end

    def mkdir(name)
      directory.join(name).tap do |dir|
        FileUtils.mkdir_p(dir)
      end
    end

    def fetch(remote_path, path, etag_path)
      if already_fetched?(remote_path)
        Gem::CompactIndexClient.debug { "already fetched #{remote_path}" }
      else
        Gem::CompactIndexClient.debug { "fetching #{remote_path}" }
        @updater&.update(remote_path, path, etag_path)
      end

      read(path)
    end

    def already_fetched?(remote_path)
      @mutex.synchronize { !@endpoints.add?(remote_path) }
    end

    def read(path)
      return unless path.file?
      path.read
    end
  end
end
