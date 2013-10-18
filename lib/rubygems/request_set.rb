require 'rubygems'
require 'rubygems/dependency'
require 'rubygems/dependency_resolver'
require 'rubygems/dependency_list'
require 'rubygems/installer'
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

    @always_install = []
    @development    = false
    @requests       = []
    @soft_missing   = false
    @sorted         = nil
    @specs          = nil
    @vendor_set     = nil

    yield self if block_given?
  end

  ##
  # Declare that a gem of name +name+ with +reqs+ requirements is needed.

  def gem name, *reqs
    @dependencies << Gem::Dependency.new(name, reqs)
  end

  ##
  # Add +deps+ Gem::Dependency objects to the set.

  def import deps
    @dependencies.concat deps
  end

  def install options, &block
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

  def install_into dir, force = true, options = {}
    existing = force ? [] : specs_in(dir)
    existing.delete_if { |s| @always_install.include? s }

    dir = File.expand_path dir

    installed = []

    sorted_requests.each do |req|
      if existing.find { |s| s.full_name == req.spec.full_name }
        yield req, nil if block_given?
        next
      end

      path = req.download(dir)

      unless path then # already installed
        yield req, nil if block_given?
        next
      end

      options[:install_dir] = dir
      options[:only_install_dir] = true

      inst = Gem::Installer.new path, options

      yield req, inst if block_given?

      inst.install

      installed << req
    end

    installed
  end

  ##
  # Load a dependency management file.

  def load_gemdeps path
    @vendor_set = Gem::DependencyResolver::VendorSet.new

    gf = Gem::RequestSet::GemDependencyAPI.new self, path
    gf.load
  end

  ##
  # Resolve the requested dependencies and return an Array of Specification
  # objects to be activated.

  def resolve set = nil
    resolver = Gem::DependencyResolver.new @dependencies, set
    resolver.development  = @development
    resolver.soft_missing = @soft_missing

    @requests = resolver.resolve
  end

  ##
  # Resolve the requested dependencies against the gems available via Gem.path
  # and return an Array of Specification objects to be activated.

  def resolve_current
    resolve Gem::DependencyResolver::CurrentSet.new
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
          raise Gem::DependencyError, "Unresolved depedency found during sorting - #{dep}"
        end
      end
    end
  end

end

require 'rubygems/request_set/gem_dependency_api'
