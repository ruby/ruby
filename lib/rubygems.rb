# -*- ruby -*-
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/rubygems_version'
require 'rubygems/defaults'
require 'thread'

module Gem
  class LoadError < ::LoadError
    attr_accessor :name, :version_requirement
  end
end

module Kernel

  # Adds a Ruby Gem to the $LOAD_PATH.  Before a Gem is loaded, its
  # required Gems are loaded.  If the version information is omitted,
  # the highest version Gem of the supplied name is loaded.  If a Gem
  # is not found that meets the version requirement and/or a required
  # Gem is not found, a Gem::LoadError is raised. More information on
  # version requirements can be found in the Gem::Version
  # documentation.
  #
  # The +gem+ directive should be executed *before* any require
  # statements (otherwise rubygems might select a conflicting library
  # version).
  #
  # You can define the environment variable GEM_SKIP as a way to not
  # load specified gems.  You might do this to test out changes that
  # haven't been installed yet.  Example:
  #
  #   GEM_SKIP=libA:libB ruby-I../libA -I../libB ./mycode.rb
  #
  # gem:: [String or Gem::Dependency] The gem name or dependency
  #       instance.
  #
  # version_requirement:: [default=">= 0"] The version
  #                       requirement.
  #
  # return:: [Boolean] true if the Gem is loaded, otherwise false.
  #
  # raises:: [Gem::LoadError] if Gem cannot be found, is listed in
  #          GEM_SKIP, or version requirement not met.
  #
  def gem(gem_name, *version_requirements)
    active_gem_with_options(gem_name, version_requirements)
  end

  # Return the file name (string) and line number (integer) of the caller of
  # the caller of this method.
  def location_of_caller
    file, lineno = caller[1].split(':')
    lineno = lineno.to_i
    [file, lineno]
  end
  private :location_of_caller

  def active_gem_with_options(gem_name, version_requirements, options={})
    skip_list = (ENV['GEM_SKIP'] || "").split(/:/)
    raise Gem::LoadError, "skipping #{gem_name}" if skip_list.include? gem_name
    Gem.activate(gem_name, options[:auto_require], *version_requirements)
  end
  private :active_gem_with_options
end

# Main module to hold all RubyGem classes/modules.
#
module Gem

  ConfigMap = {} unless defined?(ConfigMap)
  require 'rbconfig'
  RbConfig = Config unless defined? ::RbConfig
  ConfigMap.merge!(
      :BASERUBY => RbConfig::CONFIG["BASERUBY"],
      :EXEEXT => RbConfig::CONFIG["EXEEXT"],
      :RUBY_INSTALL_NAME => RbConfig::CONFIG["RUBY_INSTALL_NAME"],
      :RUBY_SO_NAME => RbConfig::CONFIG["RUBY_SO_NAME"],
      :arch => RbConfig::CONFIG["arch"],
      :bindir => RbConfig::CONFIG["bindir"],
      :libdir => RbConfig::CONFIG["libdir"],
      :ruby_install_name => RbConfig::CONFIG["ruby_install_name"],
      :ruby_version => RbConfig::CONFIG["ruby_version"],
      :sitedir => RbConfig::CONFIG["sitedir"],
      :sitelibdir => RbConfig::CONFIG["sitelibdir"]
  )

  MUTEX = Mutex.new

  RubyGemsPackageVersion = RubyGemsVersion

  DIRECTORIES = %w[cache doc gems specifications] unless defined?(DIRECTORIES)

  @@source_index = nil
  @@win_platform = nil

  @configuration = nil
  @loaded_specs = {}
  @platforms = nil
  @ruby = nil
  @sources = []

  # Reset the +dir+ and +path+ values.  The next time +dir+ or +path+
  # is requested, the values will be calculated from scratch.  This is
  # mainly used by the unit tests to provide test isolation.
  #
  def self.clear_paths
    @gem_home = nil
    @gem_path = nil
    @@source_index = nil
    MUTEX.synchronize do
      @searcher = nil
    end
  end

  # The version of the Marshal format for your Ruby.
  def self.marshal_version
    "#{Marshal::MAJOR_VERSION}.#{Marshal::MINOR_VERSION}"
  end

  ##
  # The directory prefix this RubyGems was installed at.

  def self.prefix
    prefix = File.dirname File.expand_path(__FILE__)
    if prefix == ConfigMap[:sitelibdir] then
      nil
    else
      File.dirname prefix
    end
  end

  # Returns an Cache of specifications that are in the Gem.path
  #
  # return:: [Gem::SourceIndex] Index of installed Gem::Specifications
  #
  def self.source_index
    @@source_index ||= SourceIndex.from_installed_gems
  end

  ##
  # An Array of Regexps that match windows ruby platforms.

  WIN_PATTERNS = [
    /bccwin/i,
    /cygwin/i,
    /djgpp/i,
    /mingw/i,
    /mswin/i,
    /wince/i,
  ]

  ##
  # Is this a windows platform?

  def self.win_platform?
    if @@win_platform.nil? then
      @@win_platform = !!WIN_PATTERNS.find { |r| RUBY_PLATFORM =~ r }
    end

    @@win_platform
  end

  class << self

    attr_reader :loaded_specs

    # Quietly ensure the named Gem directory contains all the proper
    # subdirectories.  If we can't create a directory due to a permission
    # problem, then we will silently continue.
    def ensure_gem_subdirectories(gemdir)
      require 'fileutils'

      Gem::DIRECTORIES.each do |filename|
        fn = File.join gemdir, filename
        FileUtils.mkdir_p fn rescue nil unless File.exist? fn
      end
    end

    def platforms
      @platforms ||= [Gem::Platform::RUBY, Gem::Platform.local]
    end

    # Returns an Array of sources to fetch remote gems from.  If the sources
    # list is empty, attempts to load the "sources" gem, then uses
    # default_sources if it is not installed.
    def sources
      if @sources.empty? then
        begin
          gem 'sources', '> 0.0.1'
          require 'sources'
        rescue LoadError
          @sources = default_sources
        end
      end

      @sources
    end


    # Provide an alias for the old name.
    alias cache source_index

    # The directory path where Gems are to be installed.
    #
    # return:: [String] The directory path
    #
    def dir
      @gem_home ||= nil
      set_home(ENV['GEM_HOME'] || default_dir) unless @gem_home
      @gem_home
    end

    # The directory path where executables are to be installed.
    #
    def bindir(install_dir=Gem.dir)
      return File.join(install_dir, 'bin') unless
        install_dir.to_s == Gem.default_dir

      if defined? RUBY_FRAMEWORK_VERSION then # mac framework support
        '/usr/bin'
      else # generic install
        ConfigMap[:bindir]
      end
    end

    # List of directory paths to search for Gems.
    #
    # return:: [List<String>] List of directory paths.
    #
    def path
      @gem_path ||= nil
      unless @gem_path
        paths = [ENV['GEM_PATH']]
        paths << APPLE_GEM_HOME if defined? APPLE_GEM_HOME
        set_paths(paths.compact.join(File::PATH_SEPARATOR))
      end
      @gem_path
    end

    # The home directory for the user.
    def user_home
      @user_home ||= find_home
    end

    # Return the path to standard location of the users .gemrc file.
    def config_file
      File.join(Gem.user_home, '.gemrc')
    end

    # The standard configuration object for gems.
    def configuration
      return @configuration if @configuration
      require 'rubygems/config_file'
      @configuration = Gem::ConfigFile.new []
    end

    # Use the given configuration object (which implements the
    # ConfigFile protocol) as the standard configuration object.
    def configuration=(config)
      @configuration = config
    end

    # Return the path the the data directory specified by the gem
    # name.  If the package is not available as a gem, return nil.
    def datadir(gem_name)
      spec = @loaded_specs[gem_name]
      return nil if spec.nil?
      File.join(spec.full_gem_path, 'data', gem_name)
    end

    # Return the searcher object to search for matching gems.
    def searcher
      MUTEX.synchronize do
        @searcher ||= Gem::GemPathSearcher.new
      end
    end

    # Return the Ruby command to use to execute the Ruby interpreter.
    def ruby
      if @ruby.nil? then
        @ruby = File.join(ConfigMap[:bindir],
                          ConfigMap[:ruby_install_name])
        @ruby << ConfigMap[:EXEEXT]
      end

      @ruby
    end

    # Activate a gem (i.e. add it to the Ruby load path).  The gem
    # must satisfy all the specified version constraints.  If
    # +autorequire+ is true, then automatically require the specified
    # autorequire file in the gem spec.
    #
    # Returns true if the gem is loaded by this call, false if it is
    # already loaded, or an exception otherwise.
    #
    def activate(gem, autorequire, *version_requirements)
      if version_requirements.empty? then
        version_requirements = Gem::Requirement.default
      end

      unless gem.respond_to?(:name) && gem.respond_to?(:version_requirements)
        gem = Gem::Dependency.new(gem, version_requirements)
      end

      matches = Gem.source_index.find_name(gem.name, gem.version_requirements)
      report_activate_error(gem) if matches.empty?

      if @loaded_specs[gem.name]
        # This gem is already loaded.  If the currently loaded gem is
        # not in the list of candidate gems, then we have a version
        # conflict.
        existing_spec = @loaded_specs[gem.name]
        if ! matches.any? { |spec| spec.version == existing_spec.version }
          fail Gem::Exception, "can't activate #{gem}, already activated #{existing_spec.full_name}]"
        end
        return false
      end

      # new load
      spec = matches.last
      if spec.loaded?
        return false unless autorequire
        result = spec.autorequire ? require(spec.autorequire) : false
        return result || false
      end

      spec.loaded = true
      @loaded_specs[spec.name] = spec

      # Load dependent gems first
      spec.dependencies.each do |dep_gem|
        activate(dep_gem, autorequire)
      end

      # bin directory must come before library directories
      spec.require_paths.unshift spec.bindir if spec.bindir

      require_paths = spec.require_paths.map do |path|
        File.join spec.full_gem_path, path
      end

      sitelibdir = ConfigMap[:sitelibdir]

      # gem directories must come after -I and ENV['RUBYLIB']
      $:.insert($:.index(sitelibdir), *require_paths)

      # Now autorequire
      if autorequire && spec.autorequire then # DEPRECATED
        Array(spec.autorequire).each do |a_lib|
          require a_lib
        end
      end

      return true
    end

    # Report a load error during activation.  The message of load
    # error depends on whether it was a version mismatch or if there
    # are not gems of any version by the requested name.
    def report_activate_error(gem)
      matches = Gem.source_index.find_name(gem.name)

      if matches.empty? then
        error = Gem::LoadError.new(
          "Could not find RubyGem #{gem.name} (#{gem.version_requirements})\n")
      else
        error = Gem::LoadError.new(
          "RubyGem version error: " +
          "#{gem.name}(#{matches.first.version} not #{gem.version_requirements})\n")
      end

      error.name = gem.name
      error.version_requirement = gem.version_requirements
      raise error
    end
    private :report_activate_error

    # Use the +home+ and (optional) +paths+ values for +dir+ and +path+.
    # Used mainly by the unit tests to provide environment isolation.
    #
    def use_paths(home, paths=[])
      clear_paths
      set_home(home) if home
      set_paths(paths.join(File::PATH_SEPARATOR)) if paths
    end

    # Return a list of all possible load paths for all versions for
    # all gems in the Gem installation.
    #
    def all_load_paths
      result = []
      Gem.path.each do |gemdir|
        each_load_path(all_partials(gemdir)) do |load_path|
          result << load_path
        end
      end
      result
    end

    # Return a list of all possible load paths for the latest version
    # for all gems in the Gem installation.
    def latest_load_paths
      result = []
      Gem.path.each do |gemdir|
        each_load_path(latest_partials(gemdir)) do |load_path|
          result << load_path
        end
      end
      result
    end

    def required_location(gemname, libfile, *version_constraints)
      version_constraints = Gem::Requirement.default if version_constraints.empty?
      matches = Gem.source_index.find_name(gemname, version_constraints)
      return nil if matches.empty?
      spec = matches.last
      spec.require_paths.each do |path|
        result = File.join(spec.full_gem_path, path, libfile)
        return result if File.exist?(result)
      end
      nil
    end

    def suffixes
      ['', '.rb', '.rbw', '.so', '.bundle', '.dll', '.sl', '.jar']
    end

    def suffix_pattern
      @suffix_pattern ||= "{#{suffixes.join(',')}}"
    end

    # manage_gems is useless and deprecated.  Don't call it anymore.  This
    # will warn in two releases.
    def manage_gems
      # do nothing
    end

    private

    # Return all the partial paths in the given +gemdir+.
    def all_partials(gemdir)
      Dir[File.join(gemdir, 'gems/*')]
    end

    # Return only the latest partial paths in the given +gemdir+.
    def latest_partials(gemdir)
      latest = {}
      all_partials(gemdir).each do |gp|
        base = File.basename(gp)
        if base =~ /(.*)-((\d+\.)*\d+)/ then
          name, version = $1, $2
          ver = Gem::Version.new(version)
          if latest[name].nil? || ver > latest[name][0]
            latest[name] = [ver, gp]
          end
        end
      end
      latest.collect { |k,v| v[1] }
    end

    # Expand each partial gem path with each of the required paths
    # specified in the Gem spec.  Each expanded path is yielded.
    def each_load_path(partials)
      partials.each do |gp|
        base = File.basename(gp)
        specfn = File.join(dir, "specifications", base + ".gemspec")
        if File.exist?(specfn)
          spec = eval(File.read(specfn))
          spec.require_paths.each do |rp|
            yield(File.join(gp, rp))
          end
        else
          filename = File.join(gp, 'lib')
          yield(filename) if File.exist?(filename)
        end
      end
    end

    # Set the Gem home directory (as reported by +dir+).
    def set_home(home)
      @gem_home = home
      ensure_gem_subdirectories(@gem_home)
    end

    # Set the Gem search path (as reported by +path+).
    def set_paths(gpaths)
      if gpaths
        @gem_path = gpaths.split(File::PATH_SEPARATOR)
        @gem_path << Gem.dir
      else
        @gem_path = [Gem.dir]
      end
      @gem_path.uniq!
      @gem_path.each do |gp| ensure_gem_subdirectories(gp) end
    end

    # Some comments from the ruby-talk list regarding finding the home
    # directory:
    #
    #   I have HOME, USERPROFILE and HOMEDRIVE + HOMEPATH. Ruby seems
    #   to be depending on HOME in those code samples. I propose that
    #   it should fallback to USERPROFILE and HOMEDRIVE + HOMEPATH (at
    #   least on Win32).
    #
    def find_home
      ['HOME', 'USERPROFILE'].each do |homekey|
        return ENV[homekey] if ENV[homekey]
      end
      if ENV['HOMEDRIVE'] && ENV['HOMEPATH']
        return "#{ENV['HOMEDRIVE']}:#{ENV['HOMEPATH']}"
      end
      begin
        File.expand_path("~")
      rescue StandardError => ex
        if File::ALT_SEPARATOR
          "C:/"
        else
          "/"
        end
      end
    end

  end

end

# Modify the non-gem version of datadir to handle gem package names.

require 'rbconfig/datadir'
module Config # :nodoc:
  class << self
    alias gem_original_datadir datadir

    # Return the path to the data directory associated with the named
    # package.  If the package is loaded as a gem, return the gem
    # specific data directory.  Otherwise return a path to the share
    # area as define by "#{ConfigMap[:datadir]}/#{package_name}".
    def datadir(package_name)
      Gem.datadir(package_name) || Config.gem_original_datadir(package_name)
    end
  end
end

require 'rubygems/exceptions'
require 'rubygems/version'
require 'rubygems/requirement'
require 'rubygems/dependency'
require 'rubygems/gem_path_searcher'    # Needed for Kernel#gem
require 'rubygems/source_index'         # Needed for Kernel#gem
require 'rubygems/platform'
require 'rubygems/builder'              # HACK: Needed for rake's package task.

if RUBY_VERSION < '1.9' then
  require 'rubygems/custom_require'
end

