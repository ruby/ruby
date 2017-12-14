require 'tsort'

##
# A RequestSet groups a request to activate a set of dependencies.
#
#   nokogiri = Gem::Dependency.new 'nokogiri', '~> 1.6'
#   pg = Gem::Dependency.new 'pg', '~> 0.14'
#
#   set = Gem::RequestSet.new nokogiri, pg
#
#   requests = set.resolve
#
#   p requests.map { |r| r.full_name }
#   #=> ["nokogiri-1.6.0", "mini_portile-0.5.1", "pg-0.17.0"]

class Gem::RequestSet

  include TSort

  ##
  # Array of gems to install even if already installed

  attr_accessor :always_install

  attr_reader :dependencies

  attr_accessor :development

  ##
  # Errors fetching gems during resolution.

  attr_reader :errors

  ##
  # Set to true if you want to install only direct development dependencies.

  attr_accessor :development_shallow

  ##
  # The set of git gems imported via load_gemdeps.

  attr_reader :git_set # :nodoc:

  ##
  # When true, dependency resolution is not performed, only the requested gems
  # are installed.

  attr_accessor :ignore_dependencies

  attr_reader :install_dir # :nodoc:

  ##
  # If true, allow dependencies to match prerelease gems.

  attr_accessor :prerelease

  ##
  # When false no remote sets are used for resolving gems.

  attr_accessor :remote

  attr_reader :resolver # :nodoc:

  ##
  # Sets used for resolution

  attr_reader :sets # :nodoc:

  ##
  # Treat missing dependencies as silent errors

  attr_accessor :soft_missing

  ##
  # The set of vendor gems imported via load_gemdeps.

  attr_reader :vendor_set # :nodoc:

  ##
  # Creates a RequestSet for a list of Gem::Dependency objects, +deps+.  You
  # can then #resolve and #install the resolved list of dependencies.
  #
  #   nokogiri = Gem::Dependency.new 'nokogiri', '~> 1.6'
  #   pg = Gem::Dependency.new 'pg', '~> 0.14'
  #
  #   set = Gem::RequestSet.new nokogiri, pg

  def initialize *deps
    @dependencies = deps

    @always_install      = []
    @conservative        = false
    @dependency_names    = {}
    @development         = false
    @development_shallow = false
    @errors              = []
    @git_set             = nil
    @ignore_dependencies = false
    @install_dir         = Gem.dir
    @prerelease          = false
    @remote              = true
    @requests            = []
    @sets                = []
    @soft_missing        = false
    @sorted              = nil
    @specs               = nil
    @vendor_set          = nil

    yield self if block_given?
  end

  ##
  # Declare that a gem of name +name+ with +reqs+ requirements is needed.

  def gem name, *reqs
    if dep = @dependency_names[name] then
      dep.requirement.concat reqs
    else
      dep = Gem::Dependency.new name, reqs
      @dependency_names[name] = dep
      @dependencies << dep
    end
  end

  ##
  # Add +deps+ Gem::Dependency objects to the set.

  def import deps
    @dependencies.concat deps
  end

  ##
  # Installs gems for this RequestSet using the Gem::Installer +options+.
  #
  # If a +block+ is given an activation +request+ and +installer+ are yielded.
  # The +installer+ will be +nil+ if a gem matching the request was already
  # installed.

  def install options, &block # :yields: request, installer
    if dir = options[:install_dir]
      requests = install_into dir, false, options, &block
      return requests
    end

    cache_dir = options[:cache_dir] || Gem.dir
    @prerelease = options[:prerelease]

    requests = []

    sorted_requests.each do |req|
      if req.installed? then
        req.spec.spec.build_extensions

        if @always_install.none? { |spec| spec == req.spec.spec } then
          yield req, nil if block_given?
          next
        end
      end

      path = req.download cache_dir

      inst = Gem::Installer.new path, options

      yield req, inst if block_given?

      requests << inst.install
    end

    requests
  ensure
    raise if $!
    return requests if options[:gemdeps]

    specs = requests.map do |request|
      case request
      when Gem::Resolver::ActivationRequest then
        request.spec.spec
      else
        request
      end
    end

    require 'rubygems/dependency_installer'
    inst = Gem::DependencyInstaller.new options
    inst.installed_gems.replace specs

    Gem.done_installing_hooks.each do |hook|
      hook.call inst, specs
    end unless Gem.done_installing_hooks.empty?
  end

  ##
  # Installs from the gem dependencies files in the +:gemdeps+ option in
  # +options+, yielding to the +block+ as in #install.
  #
  # If +:without_groups+ is given in the +options+, those groups in the gem
  # dependencies file are not used.  See Gem::Installer for other +options+.

  def install_from_gemdeps options, &block
    gemdeps = options[:gemdeps]

    @install_dir = options[:install_dir] || Gem.dir
    @prerelease  = options[:prerelease]
    @remote      = options[:domain] != :local
    @conservative = true if options[:conservative]

    gem_deps_api = load_gemdeps gemdeps, options[:without_groups], true

    resolve

    if options[:explain]
      puts "Gems to install:"

      sorted_requests.each do |spec|
        puts "  #{spec.full_name}"
      end

      if Gem.configuration.really_verbose
        @resolver.stats.display
      end
    else
      installed = install options, &block

      if options.fetch :lock, true then
        lockfile =
          Gem::RequestSet::Lockfile.new self, gemdeps, gem_deps_api.dependencies
        lockfile.write
      end

      installed
    end
  end

  def install_into dir, force = true, options = {}
    gem_home, ENV['GEM_HOME'] = ENV['GEM_HOME'], dir

    existing = force ? [] : specs_in(dir)
    existing.delete_if { |s| @always_install.include? s }

    dir = File.expand_path dir

    installed = []

    options[:development] = false
    options[:install_dir] = dir
    options[:only_install_dir] = true
    @prerelease = options[:prerelease]

    sorted_requests.each do |request|
      spec = request.spec

      if existing.find { |s| s.full_name == spec.full_name } then
        yield request, nil if block_given?
        next
      end

      spec.install options do |installer|
        yield request, installer if block_given?
      end

      installed << request
    end

    installed
  ensure
    ENV['GEM_HOME'] = gem_home
  end

  ##
  # Load a dependency management file.

  def load_gemdeps path, without_groups = [], installing = false
    @git_set    = Gem::Resolver::GitSet.new
    @vendor_set = Gem::Resolver::VendorSet.new

    @git_set.root_dir = @install_dir

    lockfile = Gem::RequestSet::Lockfile.new self, path
    lockfile.parse

    gf = Gem::RequestSet::GemDependencyAPI.new self, path
    gf.installing = installing
    gf.without_groups = without_groups if without_groups
    gf.load
  end

  def pretty_print q # :nodoc:
    q.group 2, '[RequestSet:', ']' do
      q.breakable

      if @remote then
        q.text 'remote'
        q.breakable
      end

      if @prerelease then
        q.text 'prerelease'
        q.breakable
      end

      if @development_shallow then
        q.text 'shallow development'
        q.breakable
      elsif @development then
        q.text 'development'
        q.breakable
      end

      if @soft_missing then
        q.text 'soft missing'
      end

      q.group 2, '[dependencies:', ']' do
        q.breakable
        @dependencies.map do |dep|
          q.text dep.to_s
          q.breakable
        end
      end

      q.breakable
      q.text 'sets:'

      q.breakable
      q.pp @sets.map { |set| set.class }
    end
  end

  ##
  # Resolve the requested dependencies and return an Array of Specification
  # objects to be activated.

  def resolve set = Gem::Resolver::BestSet.new
    @sets << set
    @sets << @git_set
    @sets << @vendor_set

    set = Gem::Resolver.compose_sets(*@sets)
    set.remote = @remote
    set.prerelease = @prerelease

    resolver = Gem::Resolver.new @dependencies, set
    resolver.development         = @development
    resolver.development_shallow = @development_shallow
    resolver.ignore_dependencies = @ignore_dependencies
    resolver.soft_missing        = @soft_missing

    if @conservative
      installed_gems = {}
      Gem::Specification.find_all do |spec|
        (installed_gems[spec.name] ||= []) << spec
      end
      resolver.skip_gems = installed_gems
    end

    @resolver = resolver

    @requests = resolver.resolve

    @errors = set.errors

    @requests
  end

  ##
  # Resolve the requested dependencies against the gems available via Gem.path
  # and return an Array of Specification objects to be activated.

  def resolve_current
    resolve Gem::Resolver::CurrentSet.new
  end

  def sorted_requests
    @sorted ||= strongly_connected_components.flatten
  end

  def specs
    @specs ||= @requests.map { |r| r.full_spec }
  end

  def specs_in dir
    Dir["#{dir}/specifications/*.gemspec"].map do |g|
      Gem::Specification.load g
    end
  end

  def tsort_each_node &block # :nodoc:
    @requests.each(&block)
  end

  def tsort_each_child node # :nodoc:
    node.spec.dependencies.each do |dep|
      next if dep.type == :development and not @development

      match = @requests.find { |r|
        dep.match? r.spec.name, r.spec.version, @prerelease
      }

      unless match then
        next if dep.type == :development and @development_shallow
        next if @soft_missing
        raise Gem::DependencyError,
              "Unresolved dependency found during sorting - #{dep} (requested by #{node.spec.full_name})"
      end

      yield match
    end
  end

end

require 'rubygems/request_set/gem_dependency_api'
require 'rubygems/request_set/lockfile'
