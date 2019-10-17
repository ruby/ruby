# frozen_string_literal: true
require 'rubygems'
require 'rubygems/dependency_list'
require 'rubygems/package'
require 'rubygems/installer'
require 'rubygems/spec_fetcher'
require 'rubygems/user_interaction'
require 'rubygems/source'
require 'rubygems/available_set'
require 'rubygems/deprecate'

##
# Installs a gem along with all its dependencies from local and remote gems.

class Gem::DependencyInstaller

  include Gem::UserInteraction
  extend Gem::Deprecate

  DEFAULT_OPTIONS = { # :nodoc:
    :env_shebang         => false,
    :document            => %w[ri],
    :domain              => :both, # HACK dup
    :force               => false,
    :format_executable   => false, # HACK dup
    :ignore_dependencies => false,
    :prerelease          => false,
    :security_policy     => nil, # HACK NoSecurity requires OpenSSL. AlmostNo? Low?
    :wrappers            => true,
    :build_args          => nil,
    :build_docs_in_background => false,
    :install_as_default => false
  }.freeze

  ##
  # Documentation types.  For use by the Gem.done_installing hook

  attr_reader :document

  ##
  # Errors from SpecFetcher while searching for remote specifications

  attr_reader :errors

  ##
  # List of gems installed by #install in alphabetic order

  attr_reader :installed_gems

  ##
  # Creates a new installer instance.
  #
  # Options are:
  # :cache_dir:: Alternate repository path to store .gem files in.
  # :domain:: :local, :remote, or :both.  :local only searches gems in the
  #           current directory.  :remote searches only gems in Gem::sources.
  #           :both searches both.
  # :env_shebang:: See Gem::Installer::new.
  # :force:: See Gem::Installer#install.
  # :format_executable:: See Gem::Installer#initialize.
  # :ignore_dependencies:: Don't install any dependencies.
  # :install_dir:: See Gem::Installer#install.
  # :prerelease:: Allow prerelease versions.  See #install.
  # :security_policy:: See Gem::Installer::new and Gem::Security.
  # :user_install:: See Gem::Installer.new
  # :wrappers:: See Gem::Installer::new
  # :build_args:: See Gem::Installer::new

  def initialize(options = {})
    @only_install_dir = !!options[:install_dir]
    @install_dir = options[:install_dir] || Gem.dir
    @build_root = options[:build_root]

    options = DEFAULT_OPTIONS.merge options

    @bin_dir             = options[:bin_dir]
    @dev_shallow         = options[:dev_shallow]
    @development         = options[:development]
    @document            = options[:document]
    @domain              = options[:domain]
    @env_shebang         = options[:env_shebang]
    @force               = options[:force]
    @format_executable   = options[:format_executable]
    @ignore_dependencies = options[:ignore_dependencies]
    @prerelease          = options[:prerelease]
    @security_policy     = options[:security_policy]
    @user_install        = options[:user_install]
    @wrappers            = options[:wrappers]
    @build_args          = options[:build_args]
    @build_docs_in_background = options[:build_docs_in_background]
    @install_as_default = options[:install_as_default]
    @dir_mode = options[:dir_mode]
    @data_mode = options[:data_mode]
    @prog_mode = options[:prog_mode]

    # Indicates that we should not try to update any deps unless
    # we absolutely must.
    @minimal_deps = options[:minimal_deps]

    @available      = nil
    @installed_gems = []
    @toplevel_specs = nil

    @cache_dir = options[:cache_dir] || @install_dir

    @errors = []
  end

  ##
  # Creates an AvailableSet to install from based on +dep_or_name+ and
  # +version+

  def available_set_for(dep_or_name, version) # :nodoc:
    if String === dep_or_name
      Gem::Deprecate.skip_during do
        find_spec_by_name_and_version dep_or_name, version, @prerelease
      end
    else
      dep = dep_or_name.dup
      dep.prerelease = @prerelease
      @available = Gem::Deprecate.skip_during do
        find_gems_with_sources dep
      end
    end

    @available.pick_best!
  end
  deprecate :available_set_for, :none, 2019, 12

  ##
  # Indicated, based on the requested domain, if local
  # gems should be considered.

  def consider_local?
    @domain == :both or @domain == :local
  end

  ##
  # Indicated, based on the requested domain, if remote
  # gems should be considered.

  def consider_remote?
    @domain == :both or @domain == :remote
  end

  ##
  # Returns a list of pairs of gemspecs and source_uris that match
  # Gem::Dependency +dep+ from both local (Dir.pwd) and remote (Gem.sources)
  # sources.  Gems are sorted with newer gems preferred over older gems, and
  # local gems preferred over remote gems.

  def find_gems_with_sources(dep, best_only=false) # :nodoc:
    set = Gem::AvailableSet.new

    if consider_local?
      sl = Gem::Source::Local.new

      if spec = sl.find_gem(dep.name)
        if dep.matches_spec? spec
          set.add spec, sl
        end
      end
    end

    if consider_remote?
      begin
        # This is pulled from #spec_for_dependency to allow
        # us to filter tuples before fetching specs.
        tuples, errors = Gem::SpecFetcher.fetcher.search_for_dependency dep

        if best_only && !tuples.empty?
          tuples.sort! do |a,b|
            if b[0].version == a[0].version
              if b[0].platform != Gem::Platform::RUBY
                1
              else
                -1
              end
            else
              b[0].version <=> a[0].version
            end
          end
          tuples = [tuples.first]
        end

        specs = []
        tuples.each do |tup, source|
          begin
            spec = source.fetch_spec(tup)
          rescue Gem::RemoteFetcher::FetchError => e
            errors << Gem::SourceFetchProblem.new(source, e)
          else
            specs << [spec, source]
          end
        end

        if @errors
          @errors += errors
        else
          @errors = errors
        end

        set << specs

      rescue Gem::RemoteFetcher::FetchError => e
        # FIX if there is a problem talking to the network, we either need to always tell
        # the user (no really_verbose) or fail hard, not silently tell them that we just
        # couldn't find their requested gem.
        verbose do
          "Error fetching remote data:\t\t#{e.message}\n" \
            "Falling back to local-only install"
        end
        @domain = :local
      end
    end

    set
  end
  deprecate :find_gems_with_sources, :none, 2019, 12

  ##
  # Finds a spec and the source_uri it came from for gem +gem_name+ and
  # +version+.  Returns an Array of specs and sources required for
  # installation of the gem.

  def find_spec_by_name_and_version(gem_name,
                                    version = Gem::Requirement.default,
                                    prerelease = false)
    set = Gem::AvailableSet.new

    if consider_local?
      if gem_name =~ /\.gem$/ and File.file? gem_name
        src = Gem::Source::SpecificFile.new(gem_name)
        set.add src.spec, src
      elsif gem_name =~ /\.gem$/
        Dir[gem_name].each do |name|
          begin
            src = Gem::Source::SpecificFile.new name
            set.add src.spec, src
          rescue Gem::Package::FormatError
          end
        end
      else
        local = Gem::Source::Local.new

        if s = local.find_gem(gem_name, version)
          set.add s, local
        end
      end
    end

    if set.empty?
      dep = Gem::Dependency.new gem_name, version
      dep.prerelease = true if prerelease

      set = Gem::Deprecate.skip_during do
        find_gems_with_sources(dep, true)
      end

      set.match_platform!
    end

    if set.empty?
      raise Gem::SpecificGemNotFoundException.new(gem_name, version, @errors)
    end

    @available = set
  end
  deprecate :find_spec_by_name_and_version, :none, 2019, 12

  def in_background(what) # :nodoc:
    fork_happened = false
    if @build_docs_in_background and Process.respond_to?(:fork)
      begin
        Process.fork do
          yield
        end
        fork_happened = true
        say "#{what} in a background process."
      rescue NotImplementedError
      end
    end
    yield unless fork_happened
  end

  ##
  # Installs the gem +dep_or_name+ and all its dependencies.  Returns an Array
  # of installed gem specifications.
  #
  # If the +:prerelease+ option is set and there is a prerelease for
  # +dep_or_name+ the prerelease version will be installed.
  #
  # Unless explicitly specified as a prerelease dependency, prerelease gems
  # that +dep_or_name+ depend on will not be installed.
  #
  # If c-1.a depends on b-1 and a-1.a and there is a gem b-1.a available then
  # c-1.a, b-1 and a-1.a will be installed.  b-1.a will need to be installed
  # separately.

  def install(dep_or_name, version = Gem::Requirement.default)
    request_set = resolve_dependencies dep_or_name, version

    @installed_gems = []

    options = {
      :bin_dir             => @bin_dir,
      :build_args          => @build_args,
      :document            => @document,
      :env_shebang         => @env_shebang,
      :force               => @force,
      :format_executable   => @format_executable,
      :ignore_dependencies => @ignore_dependencies,
      :prerelease          => @prerelease,
      :security_policy     => @security_policy,
      :user_install        => @user_install,
      :wrappers            => @wrappers,
      :build_root          => @build_root,
      :install_as_default  => @install_as_default,
      :dir_mode            => @dir_mode,
      :data_mode           => @data_mode,
      :prog_mode           => @prog_mode,
    }
    options[:install_dir] = @install_dir if @only_install_dir

    request_set.install options do |_, installer|
      @installed_gems << installer.spec if installer
    end

    @installed_gems.sort!

    # Since this is currently only called for docs, we can be lazy and just say
    # it's documentation. Ideally the hook adder could decide whether to be in
    # the background or not, and what to call it.
    in_background "Installing documentation" do
      Gem.done_installing_hooks.each do |hook|
        hook.call self, @installed_gems
      end
    end unless Gem.done_installing_hooks.empty?

    @installed_gems
  end

  def install_development_deps # :nodoc:
    if @development and @dev_shallow
      :shallow
    elsif @development
      :all
    else
      :none
    end
  end

  def resolve_dependencies(dep_or_name, version) # :nodoc:
    request_set = Gem::RequestSet.new
    request_set.development         = @development
    request_set.development_shallow = @dev_shallow
    request_set.soft_missing = @force
    request_set.prerelease = @prerelease
    request_set.remote = false unless consider_remote?

    installer_set = Gem::Resolver::InstallerSet.new @domain
    installer_set.ignore_installed = @only_install_dir

    if consider_local?
      if dep_or_name =~ /\.gem$/ and File.file? dep_or_name
        src = Gem::Source::SpecificFile.new dep_or_name
        installer_set.add_local dep_or_name, src.spec, src
        version = src.spec.version if version == Gem::Requirement.default
      elsif dep_or_name =~ /\.gem$/
        Dir[dep_or_name].each do |name|
          begin
            src = Gem::Source::SpecificFile.new name
            installer_set.add_local dep_or_name, src.spec, src
          rescue Gem::Package::FormatError
          end
        end
        # else This is a dependency. InstallerSet handles this case
      end
    end

    dependency =
      if spec = installer_set.local?(dep_or_name)
        Gem::Dependency.new spec.name, version
      elsif String === dep_or_name
        Gem::Dependency.new dep_or_name, version
      else
        dep_or_name
      end

    dependency.prerelease = @prerelease

    request_set.import [dependency]

    installer_set.add_always_install dependency

    request_set.always_install = installer_set.always_install

    if @ignore_dependencies
      installer_set.ignore_dependencies = true
      request_set.ignore_dependencies   = true
      request_set.soft_missing          = true
    end

    request_set.resolve installer_set

    @errors.concat request_set.errors

    request_set
  end

end
