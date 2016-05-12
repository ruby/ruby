# frozen_string_literal: true
require 'rubygems/dependency'
require 'rubygems/exceptions'
require 'rubygems/util'
require 'rubygems/util/list'

require 'uri'
require 'net/http'

##
# Given a set of Gem::Dependency objects as +needed+ and a way to query the
# set of available specs via +set+, calculates a set of ActivationRequest
# objects which indicate all the specs that should be activated to meet the
# all the requirements.

class Gem::Resolver
  require 'rubygems/resolver/molinillo'

  ##
  # If the DEBUG_RESOLVER environment variable is set then debugging mode is
  # enabled for the resolver.  This will display information about the state
  # of the resolver while a set of dependencies is being resolved.

  DEBUG_RESOLVER = !ENV['DEBUG_RESOLVER'].nil?

  ##
  # Set to true if all development dependencies should be considered.

  attr_accessor :development

  ##
  # Set to true if immediate development dependencies should be considered.

  attr_accessor :development_shallow

  ##
  # When true, no dependencies are looked up for requested gems.

  attr_accessor :ignore_dependencies

  ##
  # List of dependencies that could not be found in the configured sources.

  attr_reader :missing

  attr_reader :stats

  ##
  # Hash of gems to skip resolution.  Keyed by gem name, with arrays of
  # gem specifications as values.

  attr_accessor :skip_gems

  ##
  # When a missing dependency, don't stop. Just go on and record what was
  # missing.

  attr_accessor :soft_missing

  ##
  # Combines +sets+ into a ComposedSet that allows specification lookup in a
  # uniform manner.  If one of the +sets+ is itself a ComposedSet its sets are
  # flattened into the result ComposedSet.

  def self.compose_sets *sets
    sets.compact!

    sets = sets.map do |set|
      case set
      when Gem::Resolver::BestSet then
        set
      when Gem::Resolver::ComposedSet then
        set.sets
      else
        set
      end
    end.flatten

    case sets.length
    when 0 then
      raise ArgumentError, 'one set in the composition must be non-nil'
    when 1 then
      sets.first
    else
      Gem::Resolver::ComposedSet.new(*sets)
    end
  end

  ##
  # Creates a Resolver that queries only against the already installed gems
  # for the +needed+ dependencies.

  def self.for_current_gems needed
    new needed, Gem::Resolver::CurrentSet.new
  end

  ##
  # Create Resolver object which will resolve the tree starting
  # with +needed+ Dependency objects.
  #
  # +set+ is an object that provides where to look for specifications to
  # satisfy the Dependencies. This defaults to IndexSet, which will query
  # rubygems.org.

  def initialize needed, set = nil
    @set = set || Gem::Resolver::IndexSet.new
    @needed = needed

    @development         = false
    @development_shallow = false
    @ignore_dependencies = false
    @missing             = []
    @skip_gems           = {}
    @soft_missing        = false
    @stats               = Gem::Resolver::Stats.new
  end

  def explain stage, *data # :nodoc:
    return unless DEBUG_RESOLVER

    d = data.map { |x| x.pretty_inspect }.join(", ")
    $stderr.printf "%10s %s\n", stage.to_s.upcase, d
  end

  def explain_list stage # :nodoc:
    return unless DEBUG_RESOLVER

    data = yield
    $stderr.printf "%10s (%d entries)\n", stage.to_s.upcase, data.size
    PP.pp data, $stderr unless data.empty?
  end

  ##
  # Creates an ActivationRequest for the given +dep+ and the last +possible+
  # specification.
  #
  # Returns the Specification and the ActivationRequest

  def activation_request dep, possible # :nodoc:
    spec = possible.pop

    explain :activate, [spec.full_name, possible.size]
    explain :possible, possible

    activation_request =
      Gem::Resolver::ActivationRequest.new spec, dep, possible

    return spec, activation_request
  end

  def requests s, act, reqs=[] # :nodoc:
    return reqs if @ignore_dependencies

    s.fetch_development_dependencies if @development

    s.dependencies.reverse_each do |d|
      next if d.type == :development and not @development
      next if d.type == :development and @development_shallow and
              act.development?
      next if d.type == :development and @development_shallow and
              act.parent

      reqs << Gem::Resolver::DependencyRequest.new(d, act)
      @stats.requirement!
    end

    @set.prefetch reqs

    @stats.record_requirements reqs

    reqs
  end

  include Molinillo::UI

  def output
    @output ||= debug? ? $stdout : File.open(Gem::Util::NULL_DEVICE, 'w')
  end

  def debug?
    DEBUG_RESOLVER
  end

  include Molinillo::SpecificationProvider

  ##
  # Proceed with resolution! Returns an array of ActivationRequest objects.

  def resolve
    locking_dg = Molinillo::DependencyGraph.new
    Molinillo::Resolver.new(self, self).resolve(@needed.map { |d| DependencyRequest.new d, nil }, locking_dg).tsort.map(&:payload).compact
  rescue Molinillo::VersionConflict => e
    conflict = e.conflicts.values.first
    raise Gem::DependencyResolutionError, Conflict.new(conflict.requirement_trees.first.first, conflict.existing, conflict.requirement)
  ensure
    @output.close if defined?(@output) and !debug?
  end

  ##
  # Extracts the specifications that may be able to fulfill +dependency+ and
  # returns those that match the local platform and all those that match.

  def find_possible dependency # :nodoc:
    all = @set.find_all dependency

    if (skip_dep_gems = skip_gems[dependency.name]) && !skip_dep_gems.empty?
      matching = all.select do |api_spec|
        skip_dep_gems.any? { |s| api_spec.version == s.version }
      end

      all = matching unless matching.empty?
    end

    matching_platform = select_local_platforms all

    return matching_platform, all
  end

  ##
  # Returns the gems in +specs+ that match the local platform.

  def select_local_platforms specs # :nodoc:
    specs.select do |spec|
      Gem::Platform.installable? spec
    end
  end

  def search_for(dependency)
    possibles, all = find_possible(dependency)
    if !@soft_missing && possibles.empty?
      @missing << dependency
      exc = Gem::UnsatisfiableDependencyError.new dependency, all
      exc.errors = @set.errors
      raise exc
    end
    possibles.sort_by { |s| [s.source, s.version, Gem::Platform.local =~ s.platform ? 1 : 0] }.
      map { |s| ActivationRequest.new s, dependency, [] }
  end

  def dependencies_for(specification)
    return [] if @ignore_dependencies
    spec = specification.spec
    requests(spec, specification)
  end

  def requirement_satisfied_by?(requirement, activated, spec)
    requirement.matches_spec? spec
  end

  def name_for(dependency)
    dependency.name
  end

  def allow_missing?(dependency)
    @missing << dependency
    @soft_missing
  end

end

##
# TODO remove in RubyGems 3

Gem::DependencyResolver = Gem::Resolver # :nodoc:

require 'rubygems/resolver/activation_request'
require 'rubygems/resolver/conflict'
require 'rubygems/resolver/dependency_request'
require 'rubygems/resolver/requirement_list'
require 'rubygems/resolver/stats'

require 'rubygems/resolver/set'
require 'rubygems/resolver/api_set'
require 'rubygems/resolver/composed_set'
require 'rubygems/resolver/best_set'
require 'rubygems/resolver/current_set'
require 'rubygems/resolver/git_set'
require 'rubygems/resolver/index_set'
require 'rubygems/resolver/installer_set'
require 'rubygems/resolver/lock_set'
require 'rubygems/resolver/vendor_set'
require 'rubygems/resolver/source_set'

require 'rubygems/resolver/specification'
require 'rubygems/resolver/spec_specification'
require 'rubygems/resolver/api_specification'
require 'rubygems/resolver/git_specification'
require 'rubygems/resolver/index_specification'
require 'rubygems/resolver/installed_specification'
require 'rubygems/resolver/local_specification'
require 'rubygems/resolver/lock_specification'
require 'rubygems/resolver/vendor_specification'
