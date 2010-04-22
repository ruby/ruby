#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/user_interaction'
require 'rubygems/specification'

# :stopdoc:
module Gem
  autoload :SpecFetcher, 'rubygems/spec_fetcher'
end
# :startdoc:

##
# The SourceIndex object indexes all the gems available from a
# particular source (e.g. a list of gem directories, or a remote
# source).  A SourceIndex maps a gem full name to a gem
# specification.
#
# NOTE:: The class used to be named Cache, but that became
#        confusing when cached source fetchers where introduced. The
#        constant Gem::Cache is an alias for this class to allow old
#        YAMLized source index objects to load properly.

class Gem::SourceIndex

  include Enumerable

  include Gem::UserInteraction

  attr_reader :gems # :nodoc:

  ##
  # Directories to use to refresh this SourceIndex when calling refresh!

  attr_accessor :spec_dirs

  class << self
    include Gem::UserInteraction

    ##
    # Factory method to construct a source index instance for a given
    # path.
    #
    # deprecated::
    #   If supplied, from_installed_gems will act just like
    #   +from_gems_in+.  This argument is deprecated and is provided
    #   just for backwards compatibility, and should not generally
    #   be used.
    #
    # return::
    #   SourceIndex instance

    def from_installed_gems(*deprecated)
      if deprecated.empty?
        from_gems_in(*installed_spec_directories)
      else
        from_gems_in(*deprecated) # HACK warn
      end
    end

    ##
    # Returns a list of directories from Gem.path that contain specifications.

    def installed_spec_directories
      Gem.path.collect { |dir| File.join(dir, "specifications") }
    end

    ##
    # Creates a new SourceIndex from the ruby format gem specifications in
    # +spec_dirs+.

    def from_gems_in(*spec_dirs)
      source_index = new
      source_index.spec_dirs = spec_dirs
      source_index.refresh!
    end

    ##
    # Loads a ruby-format specification from +file_name+ and returns the
    # loaded spec.

    def load_specification(file_name)
      return nil unless file_name and File.exist? file_name

      spec_code = if defined? Encoding then
                    File.read file_name, :encoding => 'UTF-8'
                  else
                    File.read file_name
                  end.untaint

      begin
        gemspec = eval spec_code, binding, file_name

        if gemspec.is_a?(Gem::Specification)
          gemspec.loaded_from = file_name
          return gemspec
        end
        alert_warning "File '#{file_name}' does not evaluate to a gem specification"
      rescue SignalException, SystemExit
        raise
      rescue SyntaxError => e
        alert_warning e
        alert_warning spec_code
      rescue Exception => e
        alert_warning "#{e.inspect}\n#{spec_code}"
        alert_warning "Invalid .gemspec format in '#{file_name}'"
      end

      return nil
    end

  end

  ##
  # Constructs a source index instance from the provided specifications, which
  # is a Hash of gem full names and Gem::Specifications.
  #--
  # TODO merge @gems and @prerelease_gems and provide a separate method
  # #prerelease_gems

  def initialize(specifications={})
    @gems = {}
    specifications.each{ |full_name, spec| add_spec spec }
    @spec_dirs = nil
  end

  # TODO: remove method
  def all_gems
    @gems
  end

  def prerelease_gems
    @gems.reject{ |name, gem| !gem.version.prerelease? }
  end

  def released_gems
    @gems.reject{ |name, gem| gem.version.prerelease? }
  end

  ##
  # Reconstruct the source index from the specifications in +spec_dirs+.

  def load_gems_in(*spec_dirs)
    @gems.clear

    spec_dirs.reverse_each do |spec_dir|
      spec_files = Dir.glob File.join(spec_dir, '*.gemspec')

      spec_files.each do |spec_file|
        gemspec = self.class.load_specification spec_file.untaint
        add_spec gemspec if gemspec
      end
    end

    self
  end

  ##
  # Returns an Array specifications for the latest released versions
  # of each gem in this index.

  def latest_specs
    result = Hash.new { |h,k| h[k] = [] }
    latest = {}

    sort.each do |_, spec|
      name = spec.name
      curr_ver = spec.version
      prev_ver = latest.key?(name) ? latest[name].version : nil

      next if curr_ver.prerelease?
      next unless prev_ver.nil? or curr_ver >= prev_ver or
                  latest[name].platform != Gem::Platform::RUBY

      if prev_ver.nil? or
         (curr_ver > prev_ver and spec.platform == Gem::Platform::RUBY) then
        result[name].clear
        latest[name] = spec
      end

      if spec.platform != Gem::Platform::RUBY then
        result[name].delete_if do |result_spec|
          result_spec.platform == spec.platform
        end
      end

      result[name] << spec
    end

    # TODO: why is this a hash while @gems is an array? Seems like
    # structural similarity would be good.
    result.values.flatten
  end

  ##
  # An array including only the prerelease gemspecs

  def prerelease_specs
    prerelease_gems.values
  end

  ##
  # An array including only the released gemspecs

  def released_specs
    released_gems.values
  end

  ##
  # Add a gem specification to the source index.

  def add_spec(gem_spec, name = gem_spec.full_name)
    # No idea why, but the Indexer wants to insert them using original_name
    # instead of full_name. So we make it an optional arg.
    @gems[name] = gem_spec
  end

  ##
  # Add gem specifications to the source index.

  def add_specs(*gem_specs)
    gem_specs.each do |spec|
      add_spec spec
    end
  end

  ##
  # Remove a gem specification named +full_name+.

  def remove_spec(full_name)
    @gems.delete full_name
  end

  ##
  # Iterate over the specifications in the source index.

  def each(&block) # :yields: gem.full_name, gem
    @gems.each(&block)
  end

  ##
  # The gem specification given a full gem spec name.

  def specification(full_name)
    @gems[full_name]
  end

  ##
  # The signature for the source index.  Changes in the signature indicate a
  # change in the index.

  def index_signature
    require 'digest'

    Digest::SHA256.new.hexdigest(@gems.keys.sort.join(',')).to_s
  end

  ##
  # The signature for the given gem specification.

  def gem_signature(gem_full_name)
    require 'digest'

    Digest::SHA256.new.hexdigest(@gems[gem_full_name].to_yaml).to_s
  end

  def size
    @gems.size
  end
  alias length size

  ##
  # Find a gem by an exact match on the short name.

  def find_name(gem_name, version_requirement = Gem::Requirement.default)
    dep = Gem::Dependency.new gem_name, version_requirement
    search dep
  end

  ##
  # Search for a gem by Gem::Dependency +gem_pattern+.  If +only_platform+
  # is true, only gems matching Gem::Platform.local will be returned.  An
  # Array of matching Gem::Specification objects is returned.
  #
  # For backwards compatibility, a String or Regexp pattern may be passed as
  # +gem_pattern+, and a Gem::Requirement for +platform_only+.  This
  # behavior is deprecated and will be removed.

  def search(gem_pattern, platform_only = false)
    version_requirement = nil
    only_platform = false

    # TODO - Remove support and warning for legacy arguments after 2008/11
    unless Gem::Dependency === gem_pattern
      warn "#{Gem.location_of_caller.join ':'}:Warning: Gem::SourceIndex#search support for #{gem_pattern.class} patterns is deprecated, use #find_name"
    end

    case gem_pattern
    when Regexp then
      version_requirement = platform_only || Gem::Requirement.default
    when Gem::Dependency then
      only_platform = platform_only
      version_requirement = gem_pattern.requirement
      gem_pattern = if Regexp === gem_pattern.name then
                      gem_pattern.name
                    elsif gem_pattern.name.empty? then
                      //
                    else
                      /^#{Regexp.escape gem_pattern.name}$/
                    end
    else
      version_requirement = platform_only || Gem::Requirement.default
      gem_pattern = /#{gem_pattern}/i
    end

    unless Gem::Requirement === version_requirement then
      version_requirement = Gem::Requirement.create version_requirement
    end

    specs = all_gems.values.select do |spec|
      spec.name =~ gem_pattern and
        version_requirement.satisfied_by? spec.version
    end

    if only_platform then
      specs = specs.select do |spec|
        Gem::Platform.match spec.platform
      end
    end

    specs.sort_by { |s| s.sort_obj }
  end

  ##
  # Replaces the gems in the source index from specifications in the
  # directories this source index was created from.  Raises an exception if
  # this source index wasn't created from a directory (via from_gems_in or
  # from_installed_gems, or having spec_dirs set).

  def refresh!
    raise 'source index not created from disk' if @spec_dirs.nil?
    load_gems_in(*@spec_dirs)
  end

  ##
  # Returns an Array of Gem::Specifications that are not up to date.

  def outdated
    outdateds = []

    latest_specs.each do |local|
      dependency = Gem::Dependency.new local.name, ">= #{local.version}"

      begin
        fetcher = Gem::SpecFetcher.fetcher
        remotes = fetcher.find_matching dependency
        remotes = remotes.map { |(name, version,_),_| version }
      rescue Gem::RemoteFetcher::FetchError => e
        raise unless fetcher.warn_legacy e do
          require 'rubygems/source_info_cache'

          specs = Gem::SourceInfoCache.search_with_source dependency, true

          remotes = specs.map { |spec,| spec.version }
        end
      end

      latest = remotes.sort.last

      outdateds << local.name if latest and local.version < latest
    end

    outdateds
  end

  ##
  # Updates this SourceIndex from +source_uri+.  If +all+ is false, only the
  # latest gems are fetched.

  def update(source_uri, all)
    source_uri = URI.parse source_uri unless URI::Generic === source_uri
    source_uri.path += '/' unless source_uri.path =~ /\/$/

    use_incremental = false

    begin
      gem_names = fetch_quick_index source_uri, all
      remove_extra gem_names
      missing_gems = find_missing gem_names

      return false if missing_gems.size.zero?

      say "Missing metadata for #{missing_gems.size} gems" if
      missing_gems.size > 0 and Gem.configuration.really_verbose

      use_incremental = missing_gems.size <= Gem.configuration.bulk_threshold
    rescue Gem::OperationNotSupportedError => ex
      alert_error "Falling back to bulk fetch: #{ex.message}" if
      Gem.configuration.really_verbose
      use_incremental = false
    end

    if use_incremental then
      update_with_missing(source_uri, missing_gems)
    else
      new_index = fetch_bulk_index(source_uri)
      @gems.replace(new_index.gems)
    end

    true
  end

  def ==(other) # :nodoc:
    self.class === other and @gems == other.gems
  end

  def dump
    Marshal.dump(self)
  end

  private

  def fetcher
    require 'rubygems/remote_fetcher'

    Gem::RemoteFetcher.fetcher
  end

  def fetch_index_from(source_uri)
    @fetch_error = nil

    indexes = %W[
        Marshal.#{Gem.marshal_version}.Z
        Marshal.#{Gem.marshal_version}
        yaml.Z
        yaml
      ]

    indexes.each do |name|
      spec_data = nil
      index = source_uri + name
      begin
        spec_data = fetcher.fetch_path index
        spec_data = unzip(spec_data) if name =~ /\.Z$/

        if name =~ /Marshal/ then
          return Marshal.load(spec_data)
        else
          return YAML.load(spec_data)
        end
      rescue => e
        if Gem.configuration.really_verbose then
          alert_error "Unable to fetch #{name}: #{e.message}"
        end

        @fetch_error = e
      end
    end

    nil
  end

  def fetch_bulk_index(source_uri)
    say "Bulk updating Gem source index for: #{source_uri}" if
      Gem.configuration.verbose

    index = fetch_index_from(source_uri)
    if index.nil? then
      raise Gem::RemoteSourceException,
              "Error fetching remote gem cache: #{@fetch_error}"
    end
    @fetch_error = nil
    index
  end

  ##
  # Get the quick index needed for incremental updates.

  def fetch_quick_index(source_uri, all)
    index = all ? 'index' : 'latest_index'

    zipped_index = fetcher.fetch_path source_uri + "quick/#{index}.rz"

    unzip(zipped_index).split("\n")
  rescue ::Exception => e
    unless all then
      say "Latest index not found, using quick index" if
        Gem.configuration.really_verbose

      fetch_quick_index source_uri, true
    else
      raise Gem::OperationNotSupportedError,
            "No quick index found: #{e.message}"
    end
  end

  ##
  # Make a list of full names for all the missing gemspecs.

  def find_missing(spec_names)
    unless defined? @originals then
      @originals = {}
      each do |full_name, spec|
        @originals[spec.original_name] = spec
      end
    end

    spec_names.find_all { |full_name|
      @originals[full_name].nil?
    }
  end

  def remove_extra(spec_names)
    dictionary = spec_names.inject({}) { |h, k| h[k] = true; h }
    each do |name, spec|
      remove_spec name unless dictionary.include? spec.original_name
    end
  end

  ##
  # Unzip the given string.

  def unzip(string)
    require 'zlib'
    Gem.inflate string
  end

  ##
  # Tries to fetch Marshal representation first, then YAML

  def fetch_single_spec(source_uri, spec_name)
    @fetch_error = nil

    begin
      marshal_uri = source_uri + "quick/Marshal.#{Gem.marshal_version}/#{spec_name}.gemspec.rz"
      zipped = fetcher.fetch_path marshal_uri
      return Marshal.load(unzip(zipped))
    rescue => ex
      @fetch_error = ex

      if Gem.configuration.really_verbose then
        say "unable to fetch marshal gemspec #{marshal_uri}: #{ex.class} - #{ex}"
      end
    end

    begin
      yaml_uri = source_uri + "quick/#{spec_name}.gemspec.rz"
      zipped = fetcher.fetch_path yaml_uri
      return YAML.load(unzip(zipped))
    rescue => ex
      @fetch_error = ex
      if Gem.configuration.really_verbose then
        say "unable to fetch YAML gemspec #{yaml_uri}: #{ex.class} - #{ex}"
      end
    end

    nil
  end

  ##
  # Update the cached source index with the missing names.

  def update_with_missing(source_uri, missing_names)
    progress = ui.progress_reporter(missing_names.size,
        "Updating metadata for #{missing_names.size} gems from #{source_uri}")
    missing_names.each do |spec_name|
      gemspec = fetch_single_spec(source_uri, spec_name)
      if gemspec.nil? then
        ui.say "Failed to download spec #{spec_name} from #{source_uri}:\n" \
                 "\t#{@fetch_error.message}"
      else
        add_spec gemspec
        progress.updated spec_name
      end
      @fetch_error = nil
    end
    progress.done
    progress.count
  end

end

# :stopdoc:
module Gem

  ##
  # Cache is an alias for SourceIndex to allow older YAMLized source index
  # objects to load properly.

  Cache = SourceIndex

end
# :startdoc:

