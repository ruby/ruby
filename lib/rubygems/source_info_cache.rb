require 'fileutils'

require 'rubygems'
require 'rubygems/source_info_cache_entry'
require 'rubygems/user_interaction'

# SourceInfoCache stores a copy of the gem index for each gem source.
#
# There are two possible cache locations, the system cache and the user cache:
# * The system cache is prefered if it is writable or can be created.
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
#         @size => source index size
#         @source_index => Gem::SourceIndex
#       ...
#     }
#
class Gem::SourceInfoCache

  include Gem::UserInteraction

  @cache = nil
  @system_cache_file = nil
  @user_cache_file = nil

  def self.cache
    return @cache if @cache
    @cache = new
    @cache.refresh if Gem.configuration.update_sources
    @cache
  end

  def self.cache_data
    cache.cache_data
  end

  # Search all source indexes for +pattern+.
  def self.search(pattern, platform_only = false)
    cache.search pattern, platform_only
  end

  # Search all source indexes for +pattern+.  Only returns gems matching
  # Gem.platforms when +only_platform+ is true.  See #search_with_source.
  def self.search_with_source(pattern, only_platform = false)
    cache.search_with_source(pattern, only_platform)
  end

  def initialize # :nodoc:
    @cache_data = nil
    @cache_file = nil
    @dirty = false
  end

  # The most recent cache data.
  def cache_data
    return @cache_data if @cache_data
    cache_file # HACK writable check

    begin
      # Marshal loads 30-40% faster from a String, and 2MB on 20061116 is small
      data = File.open cache_file, 'rb' do |fp| fp.read end
      @cache_data = Marshal.load data

      @cache_data.each do |url, sice|
        next unless sice.is_a?(Hash)
        update
        cache = sice['cache']
        size  = sice['size']
        if cache.is_a?(Gem::SourceIndex) and size.is_a?(Numeric) then
          new_sice = Gem::SourceInfoCacheEntry.new cache, size
          @cache_data[url] = new_sice
        else # irreperable, force refetch.
          reset_cache_for(url)
        end
      end
      @cache_data
    rescue => e
      if Gem.configuration.really_verbose then
        say "Exception during cache_data handling: #{ex.class} - #{ex}"
        say "Cache file was: #{cache_file}"
        say "\t#{e.backtrace.join "\n\t"}"
      end
      reset_cache_data
    end
  end

  def reset_cache_for(url)
    say "Reseting cache for #{url}" if Gem.configuration.really_verbose

    sice = Gem::SourceInfoCacheEntry.new Gem::SourceIndex.new, 0
    sice.refresh url # HACK may be unnecessary, see ::cache and #refresh

    @cache_data[url] = sice
    @cache_data
  end

  def reset_cache_data
    @cache_data = {}
  end

  # The name of the cache file to be read
  def cache_file
    return @cache_file if @cache_file
    @cache_file = (try_file(system_cache_file) or
      try_file(user_cache_file) or
      raise "unable to locate a writable cache file")
  end

  # Write the cache to a local file (if it is dirty).
  def flush
    write_cache if @dirty
    @dirty = false
  end

  # Refreshes each source in the cache from its repository.
  def refresh
    Gem.sources.each do |source_uri|
      cache_entry = cache_data[source_uri]
      if cache_entry.nil? then
        cache_entry = Gem::SourceInfoCacheEntry.new nil, 0
        cache_data[source_uri] = cache_entry
      end

      update if cache_entry.refresh source_uri
    end

    flush
  end

  # Searches all source indexes for +pattern+.
  def search(pattern, platform_only = false)
    cache_data.map do |source_uri, sic_entry|
      next unless Gem.sources.include? source_uri
      sic_entry.source_index.search pattern, platform_only
    end.flatten.compact
  end

  # Searches all source indexes for +pattern+.  If +only_platform+ is true,
  # only gems matching Gem.platforms will be selected.  Returns an Array of
  # pairs containing the Gem::Specification found and the source_uri it was
  # found at.
  def search_with_source(pattern, only_platform = false)
    results = []

    cache_data.map do |source_uri, sic_entry|
      next unless Gem.sources.include? source_uri

      sic_entry.source_index.search(pattern, only_platform).each do |spec|
        results << [spec, source_uri]
      end
    end

    results
  end

  # Mark the cache as updated (i.e. dirty).
  def update
    @dirty = true
  end

  # The name of the system cache file.
  def system_cache_file
    self.class.system_cache_file
  end

  # The name of the system cache file. (class method)
  def self.system_cache_file
    @system_cache_file ||= Gem.default_system_source_cache_dir
  end

  # The name of the user cache file.
  def user_cache_file
    self.class.user_cache_file
  end

  # The name of the user cache file. (class method)
  def self.user_cache_file
    @user_cache_file ||=
      ENV['GEMCACHE'] || Gem.default_user_source_cache_dir
  end

  # Write data to the proper cache.
  def write_cache
    open cache_file, "wb" do |f|
      f.write Marshal.dump(cache_data)
    end
  end

  # Set the source info cache data directly.  This is mainly used for unit
  # testing when we don't want to read a file system to grab the cached source
  # index information.  The +hash+ should map a source URL into a
  # SourceInfoCacheEntry.
  def set_cache_data(hash)
    @cache_data = hash
    update
  end

  private

  # Determine if +fn+ is a candidate for a cache file.  Return fn if
  # it is.  Return nil if it is not.
  def try_file(fn)
    return fn if File.writable?(fn)
    return nil if File.exist?(fn)
    dir = File.dirname(fn)
    unless File.exist? dir then
      begin
        FileUtils.mkdir_p(dir)
      rescue RuntimeError, SystemCallError
        return nil
      end
    end
    if File.writable?(dir)
      File.open(fn, "wb") { |f| f << Marshal.dump({}) }
      return fn
    end
    nil
  end

end

