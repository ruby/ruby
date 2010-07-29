# -*- ruby -*-
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

gem_disabled = !defined? Gem

unless gem_disabled
  # Nuke the Quickloader stuff
  Gem::QuickLoader.remove
end

require 'rubygems/defaults'
require 'thread'
require 'etc'

##
# RubyGems is the Ruby standard for publishing and managing third party
# libraries.
#
# For user documentation, see:
#
# * <tt>gem help</tt> and <tt>gem help [command]</tt>
# * {RubyGems User Guide}[http://docs.rubygems.org/read/book/1]
# * {Frequently Asked Questions}[http://docs.rubygems.org/read/book/3]
#
# For gem developer documentation see:
#
# * {Creating Gems}[http://docs.rubygems.org/read/chapter/5]
# * Gem::Specification
# * Gem::Version for version dependency notes
#
# Further RubyGems documentation can be found at:
#
# * {RubyGems API}[http://rubygems.rubyforge.org/rdoc] (also available from
#   <tt>gem server</tt>)
# * {RubyGems Bookshelf}[http://rubygem.org]
#
# == RubyGems Plugins
#
# As of RubyGems 1.3.2, RubyGems will load plugins installed in gems or
# $LOAD_PATH.  Plugins must be named 'rubygems_plugin' (.rb, .so, etc) and
# placed at the root of your gem's #require_path.  Plugins are discovered via
# Gem::find_files then loaded.  Take care when implementing a plugin as your
# plugin file may be loaded multiple times if multiple versions of your gem
# are installed.
#
# For an example plugin, see the graph gem which adds a `gem graph` command.
#
# == RubyGems Defaults, Packaging
#
# RubyGems defaults are stored in rubygems/defaults.rb.  If you're packaging
# RubyGems or implementing Ruby you can change RubyGems' defaults.
#
# For RubyGems packagers, provide lib/rubygems/operating_system.rb and
# override any defaults from lib/rubygems/defaults.rb.
#
# For Ruby implementers, provide lib/rubygems/#{RUBY_ENGINE}.rb and override
# any defaults from lib/rubygems/defaults.rb.
#
# If you need RubyGems to perform extra work on install or uninstall, your
# defaults override file can set pre and post install and uninstall hooks.
# See Gem::pre_install, Gem::pre_uninstall, Gem::post_install,
# Gem::post_uninstall.
#
# == Bugs
#
# You can submit bugs to the
# {RubyGems bug tracker}[http://rubyforge.org/tracker/?atid=575&group_id=126]
# on RubyForge
#
# == Credits
#
# RubyGems is currently maintained by Eric Hodel.
#
# RubyGems was originally developed at RubyConf 2003 by:
#
# * Rich Kilmer  -- rich(at)infoether.com
# * Chad Fowler  -- chad(at)chadfowler.com
# * David Black  -- dblack(at)wobblini.net
# * Paul Brannan -- paul(at)atdesk.com
# * Jim Weirch   -- jim(at)weirichhouse.org
#
# Contributors:
#
# * Gavin Sinclair     -- gsinclair(at)soyabean.com.au
# * George Marrows     -- george.marrows(at)ntlworld.com
# * Dick Davies        -- rasputnik(at)hellooperator.net
# * Mauricio Fernandez -- batsman.geo(at)yahoo.com
# * Simon Strandgaard  -- neoneye(at)adslhome.dk
# * Dave Glasser       -- glasser(at)mit.edu
# * Paul Duncan        -- pabs(at)pablotron.org
# * Ville Aine         -- vaine(at)cs.helsinki.fi
# * Eric Hodel         -- drbrain(at)segment7.net
# * Daniel Berger      -- djberg96(at)gmail.com
# * Phil Hagelberg     -- technomancy(at)gmail.com
# * Ryan Davis         -- ryand-ruby(at)zenspider.com
#
# (If your name is missing, PLEASE let us know!)
#
# Thanks!
#
# -The RubyGems Team

module Gem
  RubyGemsVersion = VERSION = '1.3.7'

  ##
  # Raised when RubyGems is unable to load or activate a gem.  Contains the
  # name and version requirements of the gem that either conflicts with
  # already activated gems or that RubyGems is otherwise unable to activate.

  class LoadError < ::LoadError
    # Name of gem
    attr_accessor :name

    # Version requirement of gem
    attr_accessor :version_requirement
  end

  ##
  # Configuration settings from ::RbConfig

  ConfigMap = {} unless defined?(ConfigMap)

  require 'rbconfig'

  ConfigMap.merge!(
    :EXEEXT            => RbConfig::CONFIG["EXEEXT"],
    :RUBY_SO_NAME      => RbConfig::CONFIG["RUBY_SO_NAME"],
    :arch              => RbConfig::CONFIG["arch"],
    :bindir            => RbConfig::CONFIG["bindir"],
    :datadir           => RbConfig::CONFIG["datadir"],
    :libdir            => RbConfig::CONFIG["libdir"],
    :ruby_install_name => RbConfig::CONFIG["ruby_install_name"],
    :ruby_version      => RbConfig::CONFIG["ruby_version"],
    :rubylibprefix     => RbConfig::CONFIG["rubylibprefix"],
    :sitedir           => RbConfig::CONFIG["sitedir"],
    :sitelibdir        => RbConfig::CONFIG["sitelibdir"],
    :vendordir         => RbConfig::CONFIG["vendordir"] ,
    :vendorlibdir      => RbConfig::CONFIG["vendorlibdir"]
  )

  ##
  # Default directories in a gem repository

  DIRECTORIES = %w[cache doc gems specifications] unless defined?(DIRECTORIES)

  # :stopdoc:
  MUTEX = Mutex.new

  RubyGemsPackageVersion = VERSION
  # :startdoc:

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

  @@source_index = nil
  @@win_platform = nil

  @configuration = nil
  @loaded_specs = {}
  @loaded_stacks = {}
  @platforms = []
  @ruby = nil
  @sources = []

  @post_install_hooks   ||= []
  @post_uninstall_hooks ||= []
  @pre_uninstall_hooks  ||= []
  @pre_install_hooks    ||= []

  ##
  # Activates an installed gem matching +gem+.  The gem must satisfy
  # +version_requirements+.
  #
  # Returns true if the gem is activated, false if it is already
  # loaded, or an exception otherwise.
  #
  # Gem#activate adds the library paths in +gem+ to $LOAD_PATH.  Before a Gem
  # is activated its required Gems are activated.  If the version information
  # is omitted, the highest version Gem of the supplied name is loaded.  If a
  # Gem is not found that meets the version requirements or a required Gem is
  # not found, a Gem::LoadError is raised.
  #
  # More information on version requirements can be found in the
  # Gem::Requirement and Gem::Version documentation.

  def self.activate(gem, *version_requirements)
    if version_requirements.last.is_a?(Hash)
      options = version_requirements.pop
    else
      options = {}
    end

    sources = options[:sources] || []

    if version_requirements.empty? then
      version_requirements = Gem::Requirement.default
    end

    unless gem.respond_to?(:name) and
           gem.respond_to?(:requirement) then
      gem = Gem::Dependency.new(gem, version_requirements)
    end

    matches = Gem.source_index.find_name(gem.name, gem.requirement)
    report_activate_error(gem) if matches.empty?

    if @loaded_specs[gem.name] then
      # This gem is already loaded.  If the currently loaded gem is not in the
      # list of candidate gems, then we have a version conflict.
      existing_spec = @loaded_specs[gem.name]

      unless matches.any? { |spec| spec.version == existing_spec.version } then
         sources_message = sources.map { |spec| spec.full_name }
         stack_message = @loaded_stacks[gem.name].map { |spec| spec.full_name }

         msg = "can't activate #{gem} for #{sources_message.inspect}, "
         msg << "already activated #{existing_spec.full_name} for "
         msg << "#{stack_message.inspect}"

         e = Gem::LoadError.new msg
         e.name = gem.name
         e.version_requirement = gem.requirement

         raise e
      end

      return false
    end

    # new load
    spec = matches.last
    return false if spec.loaded?

    spec.loaded = true
    @loaded_specs[spec.name] = spec
    @loaded_stacks[spec.name] = sources.dup

    # Load dependent gems first
    spec.runtime_dependencies.each do |dep_gem|
      activate dep_gem, :sources => [spec, *sources]
    end

    # bin directory must come before library directories
    spec.require_paths.unshift spec.bindir if spec.bindir

    require_paths = spec.require_paths.map do |path|
      File.join spec.full_gem_path, path
    end

    # gem directories must come after -I and ENV['RUBYLIB']
    insert_index = load_path_insert_index

    if insert_index then
      # gem directories must come after -I and ENV['RUBYLIB']
      $LOAD_PATH.insert(insert_index, *require_paths)
    else
      # we are probably testing in core, -I and RUBYLIB don't apply
      $LOAD_PATH.unshift(*require_paths)
    end

    return true
  end

  ##
  # An Array of all possible load paths for all versions of all gems in the
  # Gem installation.

  def self.all_load_paths
    result = []

    Gem.path.each do |gemdir|
      each_load_path all_partials(gemdir) do |load_path|
        result << load_path
      end
    end

    result
  end

  ##
  # Return all the partial paths in +gemdir+.

  def self.all_partials(gemdir)
    Dir[File.join(gemdir, 'gems/*')]
  end

  private_class_method :all_partials

  ##
  # See if a given gem is available.

  def self.available?(gem, *requirements)
    requirements = Gem::Requirement.default if requirements.empty?

    unless gem.respond_to?(:name) and
           gem.respond_to?(:requirement) then
      gem = Gem::Dependency.new gem, requirements
    end

    !Gem.source_index.search(gem).empty?
  end

  ##
  # Find the full path to the executable for gem +name+.  If the +exec_name+
  # is not given, the gem's default_executable is chosen, otherwise the
  # specified executable's path is returned.  +version_requirements+ allows
  # you to specify specific gem versions.

  def self.bin_path(name, exec_name = nil, *version_requirements)
    version_requirements = Gem::Requirement.default if
      version_requirements.empty?
    spec = Gem.source_index.find_name(name, version_requirements).last

    raise Gem::GemNotFoundException,
          "can't find gem #{name} (#{version_requirements})" unless spec

    exec_name ||= spec.default_executable

    unless exec_name
      msg = "no default executable for #{spec.full_name}"
      raise Gem::Exception, msg
    end

    unless spec.executables.include? exec_name
      msg = "can't find executable #{exec_name} for #{spec.full_name}"
      raise Gem::Exception, msg
    end

    File.join(spec.full_gem_path, spec.bindir, exec_name)
  end

  ##
  # The mode needed to read a file as straight binary.

  def self.binary_mode
    'rb'
  end

  ##
  # The path where gem executables are to be installed.

  def self.bindir(install_dir=Gem.dir)
    return File.join(install_dir, 'bin') unless
      install_dir.to_s == Gem.default_dir
    Gem.default_bindir
  end

  ##
  # Reset the +dir+ and +path+ values.  The next time +dir+ or +path+
  # is requested, the values will be calculated from scratch.  This is
  # mainly used by the unit tests to provide test isolation.

  def self.clear_paths
    @gem_home = nil
    @gem_path = nil
    @user_home = nil

    @@source_index = nil

    MUTEX.synchronize do
      @searcher = nil
    end
  end

  ##
  # The path to standard location of the user's .gemrc file.

  def self.config_file
    File.join Gem.user_home, '.gemrc'
  end

  ##
  # The standard configuration object for gems.

  def self.configuration
    @configuration ||= Gem::ConfigFile.new []
  end

  ##
  # Use the given configuration object (which implements the ConfigFile
  # protocol) as the standard configuration object.

  def self.configuration=(config)
    @configuration = config
  end

  ##
  # The path the the data directory specified by the gem name.  If the
  # package is not available as a gem, return nil.

  def self.datadir(gem_name)
    spec = @loaded_specs[gem_name]
    return nil if spec.nil?
    File.join(spec.full_gem_path, 'data', gem_name)
  end

  ##
  # A Zlib::Deflate.deflate wrapper

  def self.deflate(data)
    require 'zlib'
    Zlib::Deflate.deflate data
  end

  ##
  # The path where gems are to be installed.

  def self.dir
    @gem_home ||= nil
    set_home(ENV['GEM_HOME'] || Gem.configuration.home || default_dir) unless @gem_home
    @gem_home
  end

  ##
  # Expand each partial gem path with each of the required paths specified
  # in the Gem spec.  Each expanded path is yielded.

  def self.each_load_path(partials)
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

  private_class_method :each_load_path

  ##
  # Quietly ensure the named Gem directory contains all the proper
  # subdirectories.  If we can't create a directory due to a permission
  # problem, then we will silently continue.

  def self.ensure_gem_subdirectories(gemdir)
    require 'fileutils'

    Gem::DIRECTORIES.each do |filename|
      fn = File.join gemdir, filename
      FileUtils.mkdir_p fn rescue nil unless File.exist? fn
    end
  end

  ##
  # Returns a list of paths matching +file+ that can be used by a gem to pick
  # up features from other gems.  For example:
  #
  #   Gem.find_files('rdoc/discover').each do |path| load path end
  #
  # find_files search $LOAD_PATH for files as well as gems.
  #
  # Note that find_files will return all files even if they are from different
  # versions of the same gem.

  def self.find_files(path)
    load_path_files = $LOAD_PATH.map do |load_path|
      files = Dir["#{File.expand_path path, load_path}#{Gem.suffix_pattern}"]

      files.select do |load_path_file|
        File.file? load_path_file.untaint
      end
    end.flatten

    specs = searcher.find_all path

    specs_files = specs.map do |spec|
      searcher.matching_files spec, path
    end.flatten

    (load_path_files + specs_files).flatten.uniq
  end

  ##
  # Finds the user's home directory.

  def self.find_home
    File.expand_path "~"
  rescue
    if File::ALT_SEPARATOR then
      "C:/"
    else
      "/"
    end
  end

  private_class_method :find_home

  ##
  # Zlib::GzipReader wrapper that unzips +data+.

  def self.gunzip(data)
    require 'stringio'
    require 'zlib'
    data = StringIO.new data

    Zlib::GzipReader.new(data).read
  end

  ##
  # Zlib::GzipWriter wrapper that zips +data+.

  def self.gzip(data)
    require 'stringio'
    require 'zlib'
    zipped = StringIO.new

    Zlib::GzipWriter.wrap zipped do |io| io.write data end

    zipped.string
  end

  ##
  # A Zlib::Inflate#inflate wrapper

  def self.inflate(data)
    require 'zlib'
    Zlib::Inflate.inflate data
  end

  ##
  # Return a list of all possible load paths for the latest version for all
  # gems in the Gem installation.

  def self.latest_load_paths
    result = []

    Gem.path.each do |gemdir|
      each_load_path(latest_partials(gemdir)) do |load_path|
        result << load_path
      end
    end

    result
  end

  ##
  # Return only the latest partial paths in the given +gemdir+.

  def self.latest_partials(gemdir)
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

  private_class_method :latest_partials

  ##
  # The index to insert activated gem paths into the $LOAD_PATH.
  #
  # Defaults to the site lib directory unless gem_prelude.rb has loaded paths,
  # then it inserts the activated gem's paths before the gem_prelude.rb paths
  # so you can override the gem_prelude.rb default $LOAD_PATH paths.

  def self.load_path_insert_index
    $LOAD_PATH.index { |p| p.instance_variable_defined? :@gem_prelude_index }
  end

  def self.remove_prelude_paths
    Gem::QuickLoader::GemLoadPaths.each do |path|
      $LOAD_PATH.delete(path)
    end
  end

  ##
  # The file name and line number of the caller of the caller of this method.

  def self.location_of_caller
    caller[1] =~ /(.*?):(\d+).*?$/i
    file = $1
    lineno = $2.to_i

    [file, lineno]
  end

  ##
  # The version of the Marshal format for your Ruby.

  def self.marshal_version
    "#{Marshal::MAJOR_VERSION}.#{Marshal::MINOR_VERSION}"
  end

  ##
  # Array of paths to search for Gems.

  def self.path
    @gem_path ||= nil

    unless @gem_path then
      paths = [ENV['GEM_PATH'] || Gem.configuration.path || default_path]

      if defined?(APPLE_GEM_HOME) and not ENV['GEM_PATH'] then
        paths << APPLE_GEM_HOME
      end

      set_paths paths.compact.join(File::PATH_SEPARATOR)
    end

    @gem_path
  end

  ##
  # Set array of platforms this RubyGems supports (primarily for testing).

  def self.platforms=(platforms)
    @platforms = platforms
  end

  ##
  # Array of platforms this RubyGems supports.

  def self.platforms
    @platforms ||= []
    if @platforms.empty?
      @platforms = [Gem::Platform::RUBY, Gem::Platform.local]
    end
    @platforms
  end

  ##
  # Adds a post-install hook that will be passed an Gem::Installer instance
  # when Gem::Installer#install is called

  def self.post_install(&hook)
    @post_install_hooks << hook
  end

  ##
  # Adds a post-uninstall hook that will be passed a Gem::Uninstaller instance
  # and the spec that was uninstalled when Gem::Uninstaller#uninstall is
  # called

  def self.post_uninstall(&hook)
    @post_uninstall_hooks << hook
  end

  ##
  # Adds a pre-install hook that will be passed an Gem::Installer instance
  # when Gem::Installer#install is called

  def self.pre_install(&hook)
    @pre_install_hooks << hook
  end

  ##
  # Adds a pre-uninstall hook that will be passed an Gem::Uninstaller instance
  # and the spec that will be uninstalled when Gem::Uninstaller#uninstall is
  # called

  def self.pre_uninstall(&hook)
    @pre_uninstall_hooks << hook
  end

  ##
  # The directory prefix this RubyGems was installed at.

  def self.prefix
    dir = File.dirname File.expand_path(__FILE__)
    prefix = File.dirname dir

    if prefix == File.expand_path(ConfigMap[:sitelibdir]) or
       prefix == File.expand_path(ConfigMap[:libdir]) or
       'lib' != File.basename(dir) then
      nil
    else
      prefix
    end
  end

  ##
  # Promotes the load paths of the +gem_name+ over the load paths of
  # +over_name+.  Useful for allowing one gem to override features in another
  # using #find_files.

  def self.promote_load_path(gem_name, over_name)
    gem = Gem.loaded_specs[gem_name]
    over = Gem.loaded_specs[over_name]

    raise ArgumentError, "gem #{gem_name} is not activated" if gem.nil?
    raise ArgumentError, "gem #{over_name} is not activated" if over.nil?

    last_gem_path = File.join gem.full_gem_path, gem.require_paths.last

    over_paths = over.require_paths.map do |path|
      File.join over.full_gem_path, path
    end

    over_paths.each do |path|
      $LOAD_PATH.delete path
    end

    gem = $LOAD_PATH.index(last_gem_path) + 1

    $LOAD_PATH.insert(gem, *over_paths)
  end

  ##
  # Refresh source_index from disk and clear searcher.

  def self.refresh
    source_index.refresh!

    MUTEX.synchronize do
      @searcher = nil
    end
  end

  ##
  # Safely read a file in binary mode on all platforms.

  def self.read_binary(path)
    File.open path, binary_mode do |f| f.read end
  end

  ##
  # Report a load error during activation.  The message of load error
  # depends on whether it was a version mismatch or if there are not gems of
  # any version by the requested name.

  def self.report_activate_error(gem)
    matches = Gem.source_index.find_name(gem.name)

    if matches.empty? then
      error = Gem::LoadError.new(
          "Could not find RubyGem #{gem.name} (#{gem.requirement})\n")
    else
      error = Gem::LoadError.new(
          "RubyGem version error: " +
          "#{gem.name}(#{matches.first.version} not #{gem.requirement})\n")
    end

    error.name = gem.name
    error.version_requirement = gem.requirement
    raise error
  end

  private_class_method :report_activate_error

  ##
  # Full path to +libfile+ in +gemname+.  Searches for the latest gem unless
  # +requirements+ is given.

  def self.required_location(gemname, libfile, *requirements)
    requirements = Gem::Requirement.default if requirements.empty?

    matches = Gem.source_index.find_name gemname, requirements

    return nil if matches.empty?

    spec = matches.last
    spec.require_paths.each do |path|
      result = File.join spec.full_gem_path, path, libfile
      return result if File.exist? result
    end

    nil
  end

  ##
  # The path to the running Ruby interpreter.

  def self.ruby
    if @ruby.nil? then
      @ruby = File.join(ConfigMap[:bindir],
                        ConfigMap[:ruby_install_name])
      @ruby << ConfigMap[:EXEEXT]

      # escape string in case path to ruby executable contain spaces.
      @ruby.sub!(/.*\s.*/m, '"\&"')
    end

    @ruby
  end

  ##
  # A Gem::Version for the currently running ruby.

  def self.ruby_version
    return @ruby_version if defined? @ruby_version
    version = RUBY_VERSION.dup

    if defined?(RUBY_PATCHLEVEL) && RUBY_PATCHLEVEL != -1 then
      version << ".#{RUBY_PATCHLEVEL}"
    elsif defined?(RUBY_REVISION) then
      version << ".dev.#{RUBY_REVISION}"
    end

    @ruby_version = Gem::Version.new version
  end

  ##
  # The GemPathSearcher object used to search for matching installed gems.

  def self.searcher
    MUTEX.synchronize do
      @searcher ||= Gem::GemPathSearcher.new
    end
  end

  ##
  # Set the Gem home directory (as reported by Gem.dir).

  def self.set_home(home)
    home = home.gsub File::ALT_SEPARATOR, File::SEPARATOR if File::ALT_SEPARATOR
    @gem_home = home
  end

  private_class_method :set_home

  ##
  # Set the Gem search path (as reported by Gem.path).

  def self.set_paths(gpaths)
    if gpaths
      @gem_path = gpaths.split(File::PATH_SEPARATOR)

      if File::ALT_SEPARATOR then
        @gem_path.map! do |path|
          path.gsub File::ALT_SEPARATOR, File::SEPARATOR
        end
      end

      @gem_path << Gem.dir
    else
      # TODO: should this be Gem.default_path instead?
      @gem_path = [Gem.dir]
    end

    @gem_path.uniq!
  end

  private_class_method :set_paths

  ##
  # Returns the Gem::SourceIndex of specifications that are in the Gem.path

  def self.source_index
    @@source_index ||= SourceIndex.from_installed_gems
  end

  ##
  # Returns an Array of sources to fetch remote gems from.  If the sources
  # list is empty, attempts to load the "sources" gem, then uses
  # default_sources if it is not installed.

  def self.sources
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

  ##
  # Need to be able to set the sources without calling
  # Gem.sources.replace since that would cause an infinite loop.

  def self.sources=(new_sources)
    @sources = new_sources
  end

  ##
  # Glob pattern for require-able path suffixes.

  def self.suffix_pattern
    @suffix_pattern ||= "{#{suffixes.join(',')}}"
  end

  ##
  # Suffixes for require-able paths.

  def self.suffixes
    ['', '.rb', '.rbw', '.so', '.bundle', '.dll', '.sl', '.jar']
  end

  ##
  # Prints the amount of time the supplied block takes to run using the debug
  # UI output.

  def self.time(msg, width = 0, display = Gem.configuration.verbose)
    now = Time.now

    value = yield

    elapsed = Time.now - now

    ui.say "%2$*1$s: %3$3.3fs" % [-width, msg, elapsed] if display

    value
  end

  ##
  # Lazily loads DefaultUserInteraction and returns the default UI.

  def self.ui
    require 'rubygems/user_interaction'

    Gem::DefaultUserInteraction.ui
  end

  ##
  # Use the +home+ and +paths+ values for Gem.dir and Gem.path.  Used mainly
  # by the unit tests to provide environment isolation.

  def self.use_paths(home, paths=[])
    clear_paths
    set_home(home) if home
    set_paths(paths.join(File::PATH_SEPARATOR)) if paths
  end

  ##
  # The home directory for the user.

  def self.user_home
    @user_home ||= find_home
  end

  ##
  # Is this a windows platform?

  def self.win_platform?
    if @@win_platform.nil? then
      @@win_platform = !!WIN_PATTERNS.find { |r| RUBY_PLATFORM =~ r }
    end

    @@win_platform
  end

  ##
  # Find all 'rubygems_plugin' files and load them

  def self.load_plugins
    plugins = Gem.find_files 'rubygems_plugin'

    plugins.each do |plugin|

      # Skip older versions of the GemCutter plugin: Its commands are in
      # RubyGems proper now.

      next if plugin =~ /gemcutter-0\.[0-3]/

      begin
        load plugin
      rescue ::Exception => e
        details = "#{plugin.inspect}: #{e.message} (#{e.class})"
        warn "Error loading RubyGems plugin #{details}"
      end
    end
  end

  class << self

    ##
    # Hash of loaded Gem::Specification keyed by name

    attr_reader :loaded_specs

    ##
    # The list of hooks to be run before Gem::Install#install does any work

    attr_reader :post_install_hooks

    ##
    # The list of hooks to be run before Gem::Uninstall#uninstall does any
    # work

    attr_reader :post_uninstall_hooks

    ##
    # The list of hooks to be run after Gem::Install#install is finished

    attr_reader :pre_install_hooks

    ##
    # The list of hooks to be run after Gem::Uninstall#uninstall is finished

    attr_reader :pre_uninstall_hooks

    # :stopdoc:

    alias cache source_index # an alias for the old name

    # :startdoc:

  end

  ##
  # Location of Marshal quick gemspecs on remote repositories

  MARSHAL_SPEC_DIR = "quick/Marshal.#{Gem.marshal_version}/"

  ##
  # Location of legacy YAML quick gemspecs on remote repositories

  YAML_SPEC_DIR = 'quick/'

end

module Kernel

  remove_method :gem if respond_to?(:gem, true) # defined in gem_prelude.rb on 1.9

  ##
  # Use Kernel#gem to activate a specific version of +gem_name+.
  #
  # +version_requirements+ is a list of version requirements that the
  # specified gem must match, most commonly "= example.version.number".  See
  # Gem::Requirement for how to specify a version requirement.
  #
  # If you will be activating the latest version of a gem, there is no need to
  # call Kernel#gem, Kernel#require will do the right thing for you.
  #
  # Kernel#gem returns true if the gem was activated, otherwise false.  If the
  # gem could not be found, didn't match the version requirements, or a
  # different version was already activated, an exception will be raised.
  #
  # Kernel#gem should be called *before* any require statements (otherwise
  # RubyGems may load a conflicting library version).
  #
  # In older RubyGems versions, the environment variable GEM_SKIP could be
  # used to skip activation of specified gems, for example to test out changes
  # that haven't been installed yet.  Now RubyGems defers to -I and the
  # RUBYLIB environment variable to skip activation of a gem.
  #
  # Example:
  #
  #   GEM_SKIP=libA:libB ruby -I../libA -I../libB ./mycode.rb

  def gem(gem_name, *version_requirements) # :doc:
    skip_list = (ENV['GEM_SKIP'] || "").split(/:/)
    raise Gem::LoadError, "skipping #{gem_name}" if skip_list.include? gem_name
    Gem.activate(gem_name, *version_requirements)
  end

  private :gem

end

##
# Return the path to the data directory associated with the named package.  If
# the package is loaded as a gem, return the gem specific data directory.
# Otherwise return a path to the share area as define by
# "#{ConfigMap[:datadir]}/#{package_name}".

def RbConfig.datadir(package_name)
  Gem.datadir(package_name) ||
    File.join(Gem::ConfigMap[:datadir], package_name)
end

require 'rubygems/exceptions'
require 'rubygems/version'
require 'rubygems/requirement'
require 'rubygems/dependency'
require 'rubygems/gem_path_searcher'    # Needed for Kernel#gem
require 'rubygems/source_index'         # Needed for Kernel#gem
require 'rubygems/platform'
require 'rubygems/builder'              # HACK: Needed for rake's package task.

begin
  ##
  # Defaults the operating system (or packager) wants to provide for RubyGems.

  require 'rubygems/defaults/operating_system'
rescue LoadError
end

if defined?(RUBY_ENGINE) then
  begin
    ##
    # Defaults the ruby implementation wants to provide for RubyGems

    require "rubygems/defaults/#{RUBY_ENGINE}"
  rescue LoadError
  end
end

require 'rubygems/config_file'

class << Gem
  remove_method :try_activate if Gem.respond_to?(:try_activate, true)

  def try_activate(path)
    spec = Gem.searcher.find(path)
    return false unless spec

    Gem.activate(spec.name, "= #{spec.version}")
    return true
  end
end

##
# Enables the require hook for RubyGems.
#
# if --disable-rubygems was used, then the prelude wasn't loaded, so
# we need to load the custom_require now.

if gem_disabled
  require 'rubygems/custom_require'
end

Gem.clear_paths

Gem.load_plugins

