require 'fileutils'

require 'rubygems'
require 'rubygems/source_info_cache_entry'
require 'rubygems/user_interaction'

##
# SourceInfoCache stores a copy of the gem index for each gem source.
#
# There are two possible cache locations, the system cache and the user cache:
# * The system cache is preferred if it is writable or can be created.
# * The user cache is used otherwise
#
# Once a cache is selected, it will be used for all operations.
# SourceInfoCache will not switch between cache files dynamically.
#
# Cache data is a Hash mapping a source URI to a SourceInfoCacheEntry.
#
#--
# To keep things straight, this is how the cache objects all fit together:
#
#   Gem::SourceInfoCache
#     @cache_data = {
#       source_uri => Gem::SourceInfoCacheEntry
#         @size = source index size
#         @source_index = Gem::SourceIndex
#       ...
#     }

class Gem::SourceInfoCache

  include Gem::UserInteraction

  ##
  # The singleton Gem::SourceInfoCache.  If +all+ is true, a full refresh will
  # be performed if the singleton instance is being initialized.

  def self.cache(all = false)
    return @cache if @cache
    @cache = new
    @cache.refresh all if Gem.configuration.update_sources
    @cache
  end

  def self.cache_data
    cache.cache_data
  end

  ##
  # The name of the system cache file.

  def self.latest_system_cache_file
    File.join File.dirname(system_cache_file),
              "latest_#{File.basename system_cache_file}"
  end

  ##
  # The name of the latest user cache file.

  def self.latest_user_cache_file
    File.join File.dirname(user_cache_file),
              "latest_#{File.basename user_cache_file}"
  end

  ##
  # Reset all singletons, discarding any changes.

  def self.reset
    @cache = nil
    @system_cache_file = nil
    @user_cache_file = nil
  end

  ##
  # Search all source indexes.  See Gem::SourceInfoCache#search.

  def self.search(*args)
    cache.search(*args)
  end

  ##
  # Search all source indexes returning the source_uri.  See
  # Gem::SourceInfoCache#search_with_source.

  def self.search_with_source(*args)
    cache.search_with_source(*args)
  end

  ##
  # The name of the system cache file. (class method)

  def self.system_cache_file
    @system_cache_file ||= Gem.default_system_source_cache_dir
  end

  ##
  # The name of the user cache file.

  def self.user_cache_file
    @user_cache_file ||=
      ENV['GEMCACHE'] || Gem.default_user_source_cache_dir
  end

  def initialize # :nodoc:
    @cache_data = nil
    @cache_file = nil
    @dirty = false
    @only_latest = true
  end

  ##
  # The most recent cache data.

  def cache_data
    return @cache_data if @cache_data
    cache_file # HACK writable check

    @only_latest = true

    @cache_data = read_cache_data latest_cache_file

    @cache_data
  end

  ##
  # The name of the cache file.

  def cache_file
    return @cache_file if @cache_file
    @cache_file = (try_file(system_cache_file) or
      try_file(user_cache_file) or
      raise "unable to locate a writable cache file")
  end

  ##
  # Write the cache to a local file (if it is dirty).

  def flush
    write_cache if @dirty
    @dirty = false
  end

  def latest_cache_data
    latest_cache_data = {}

    cache_data.each do |repo, sice|
      latest = sice.source_index.latest_specs

      new_si = Gem::SourceIndex.new
      new_si.add_specs(*latest)

      latest_sice = Gem::SourceInfoCacheEntry.new new_si, sice.size
      latest_cache_data[repo] = latest_sice
    end

    latest_cache_data
  end

  ##
  # The name of the latest cache file.

  def latest_cache_file
    File.join File.dirname(cache_file), "latest_#{File.basename cache_file}"
  end

  ##
  # The name of the latest system cache file.

  def latest_system_cache_file
    self.class.latest_system_cache_file
  end

  ##
  # The name of the latest user cache file.

  def latest_user_cache_file
    self.class.latest_user_cache_file
  end

  ##
  # Merges the complete cache file into this Gem::SourceInfoCache.

  def read_all_cache_data
    if @only_latest then
      @only_latest = false
      all_data = read_cache_data cache_file

      cache_data.update all_data do |source_uri, latest_sice, all_sice|
        all_sice.source_index.gems.update latest_sice.source_index.gems

        Gem::SourceInfoCacheEntry.new all_sice.source_index, latest_sice.size
      end

      begin
        refresh true
      rescue Gem::RemoteFetcher::FetchError
      end
    end
  end

  ##
  # Reads cached data from +file+.

  def read_cache_data(file)
    # Marshal loads 30-40% faster from a String, and 2MB on 20061116 is small
    data = open file, 'rb' do |fp| fp.read end
    cache_data = Marshal.load data

    cache_data.each do |url, sice|
      next unless sice.is_a?(Hash)
      update

      cache = sice['cache']
      size  = sice['size']

      if cache.is_a?(Gem::SourceIndex) and size.is_a?(Numeric) then
        new_sice = Gem::SourceInfoCacheEntry.new cache, size
        cache_data[url] = new_sice
      else # irreperable, force refetch.
        reset_cache_for url, cache_data
      end
    end

    cache_data
  rescue Errno::ENOENT
    {}
  rescue => e
    if Gem.configuration.really_verbose then
      say "Exception during cache_data handling: #{e.class} - #{e}"
      say "Cache file was: #{file}"
      say "\t#{e.backtrace.join "\n\t"}"
    end

    {}
  end

  ##
  # Refreshes each source in the cache from its repository.  If +all+ is
  # false, only latest gems are updated.

  def refresh(all)
    Gem.sources.each do |source_uri|
      cache_entry = cache_data[source_uri]
      if cache_entry.nil? then
        cache_entry = Gem::SourceInfoCacheEntry.new nil, 0
        cache_data[source_uri] = cache_entry
      end

      update if cache_entry.refresh source_uri, all
    end

    flush
  end

  def reset_cache_for(url, cache_data)
    say "Reseting cache for #{url}" if Gem.configuration.really_verbose

    sice = Gem::SourceInfoCacheEntry.new Gem::SourceIndex.new, 0
    sice.refresh url, false # HACK may be unnecessary, see ::cache and #refresh

    cache_data[url] = sice
    cache_data
  end

  def reset_cache_data
    @cache_data = nil
    @only_latest = true
  end

  ##
  # Force cache file to be reset, useful for integration testing of rubygems

  def reset_cache_file
    @cache_file = nil
  end

  ##
  # Searches all source indexes.  See Gem::SourceIndex#search for details on
  # +pattern+ and +platform_only+.  If +all+ is set to true, the full index
  # will be loaded before searching.

  def search(pattern, platform_only = false, all = false)
    read_all_cache_data if all

    cache_data.map do |source_uri, sic_entry|
      next unless Gem.sources.include? source_uri
      sic_entry.source_index.search pattern, platform_only
    end.flatten.compact
  end

  # Searches all source indexes for +pattern+.  If +only_platform+ is true,
  # only gems matching Gem.platforms will be selected.  Returns an Array of
  # pairs containing the Gem::Specification found and the source_uri it was
  # found at.
  def search_with_source(pattern, only_platform = false, all = false)
    read_all_cache_data if all

    results = []

    cache_data.map do |source_uri, sic_entry|
      next unless Gem.sources.include? source_uri

      sic_entry.source_index.search(pattern, only_platform).each do |spec|
        results << [spec, source_uri]
      end
    end

    results
  end

  ##
  # Set the source info cache data directly.  This is mainly used for unit
  # testing when we don't want to read a file system to grab the cached source
  # index information.  The +hash+ should map a source URL into a
  # SourceInfoCacheEntry.

  def set_cache_data(hash)
    @cache_data = hash
    update
  end

  ##
  # The name of the system cache file.

  def system_cache_file
    self.class.system_cache_file
  end

  ##
  # Determine if +path+ is a candidate for a cache file.  Returns +path+ if
  # it is, nil if not.

  def try_file(path)
    return path if File.writable? path
    return nil if File.exist? path

    dir = File.dirname path

    unless File.exist? dir then
      begin
        FileUtils.mkdir_p dir
      rescue RuntimeError, SystemCallError
        return nil
      end
    end

    return path if File.writable? dir

    nil
  end

  ##
  # Mark the cache as updated (i.e. dirty).

  def update
    @dirty = true
  end

  ##
  # The name of the user cache file.

  def user_cache_file
    self.class.user_cache_file
  end

  ##
  # Write data to the proper cache files.

  def write_cache
    if not File.exist?(cache_file) or not @only_latest then
      open cache_file, 'wb' do |io|
        io.write Marshal.dump(cache_data)
      end
    end

    open latest_cache_file, 'wb' do |io|
      io.write Marshal.dump(latest_cache_data)
    end
  end

  reset

end

