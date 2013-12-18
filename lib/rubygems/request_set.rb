require 'rubygems'
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

  attr_reader :always_install

  attr_reader :dependencies

  attr_accessor :development

  ##
  # The set of git gems imported via load_gemdeps.

  attr_reader :git_set # :nodoc:

  ##
  # When true, dependency resolution is not performed, only the requested gems
  # are installed.

  attr_accessor :ignore_dependencies

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
    @dependency_names    = {}
    @development         = false
    @git_set             = nil
    @ignore_dependencies = false
    @install_dir         = Gem.dir
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
      return install_into dir, false, options, &block
    end

    cache_dir = options[:cache_dir] || Gem.dir

    specs = []

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

      specs << inst.install
    end

    specs
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

    load_gemdeps gemdeps, options[:without_groups]

    resolve

    if options[:explain]
      puts "Gems to install:"

      specs.map { |s| s.full_name }.sort.each do |s|
        puts "  #{s}"
      end

      if Gem.configuration.really_verbose
        @resolver.stats.display
      end
    else
      installed = install options, &block

      lockfile = Gem::RequestSet::Lockfile.new self, gemdeps
      lockfile.write

      installed
    end
  end

  def install_into dir, force = true, options = {}
    gem_home, ENV['GEM_HOME'] = ENV['GEM_HOME'], dir

    existing = force ? [] : specs_in(dir)
    existing.delete_if { |s| @always_install.include? s }

    dir = File.expand_path dir

    installed = []

    options[:install_dir] = dir
    options[:only_install_dir] = true

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

  def load_gemdeps path, without_groups = []
    @git_set    = Gem::Resolver::GitSet.new
    @vendor_set = Gem::Resolver::VendorSet.new

    @git_set.root_dir = @install_dir

    lockfile = Gem::RequestSet::Lockfile.new self, path
    lockfile.parse

    gf = Gem::RequestSet::GemDependencyAPI.new self, path
    gf.without_groups = without_groups if without_groups
    gf.load
  end

  ##
  # Resolve the requested dependencies and return an Array of Specification
  # objects to be activated.

  def resolve set = Gem::Resolver::BestSet.new
    @sets << set
    @sets << @git_set
    @sets << @vendor_set

    set = Gem::Resolver.compose_sets(*@sets)

    resolver = Gem::Resolver.new @dependencies, set
    resolver.development         = @development
    resolver.ignore_dependencies = @ignore_dependencies
    resolver.soft_missing        = @soft_missing

    @resolver = resolver

    @requests = resolver.resolve
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

      match = @requests.find { |r| dep.match? r.spec.name, r.spec.version }
      if match
        begin
          yield match
        rescue TSort::Cyclic
        end
      else
        unless @soft_missing
          raise Gem::DependencyError, "Unresolved dependency found during sorting - #{dep} (requested by #{node.spec.full_name})"
        end
      end
    end
  end

end

require 'rubygems/request_set/gem_dependency_api'
require 'rubygems/request_set/lockfile'
