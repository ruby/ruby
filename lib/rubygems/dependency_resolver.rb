require 'rubygems'
require 'rubygems/dependency'
require 'rubygems/exceptions'
require 'rubygems/util/list'

require 'uri'
require 'net/http'

##
# Given a set of Gem::Dependency objects as +needed+ and a way to query the
# set of available specs via +set+, calculates a set of ActivationRequest
# objects which indicate all the specs that should be activated to meet the
# all the requirements.

class Gem::DependencyResolver

  ##
  # Contains all the conflicts encountered while doing resolution

  attr_reader :conflicts

  attr_accessor :development

  attr_reader :missing

  ##
  # When a missing dependency, don't stop. Just go on and record what was
  # missing.

  attr_accessor :soft_missing

  def self.compose_sets *sets
    sets.compact!

    case sets.length
    when 0 then
      raise ArgumentError, 'one set in the composition must be non-nil'
    when 1 then
      sets.first
    else
      Gem::DependencyResolver::ComposedSet.new(*sets)
    end
  end

  ##
  # Provide a DependencyResolver that queries only against the already
  # installed gems.

  def self.for_current_gems needed
    new needed, Gem::DependencyResolver::CurrentSet.new
  end

  ##
  # Create DependencyResolver object which will resolve the tree starting
  # with +needed+ Dependency objects.
  #
  # +set+ is an object that provides where to look for specifications to
  # satisfy the Dependencies. This defaults to IndexSet, which will query
  # rubygems.org.

  def initialize needed, set = nil
    @set = set || Gem::DependencyResolver::IndexSet.new
    @needed = needed

    @conflicts    = []
    @development  = false
    @missing      = []
    @soft_missing = false
  end

  ##
  # Creates an ActivationRequest for the given +dep+ and the last +possible+
  # specification.
  #
  # Returns the Specification and the ActivationRequest

  def activation_request dep, possible # :nodoc:
    spec = possible.pop

    activation_request =
      Gem::DependencyResolver::ActivationRequest.new spec, dep, possible

    return spec, activation_request
  end

  def requests s, act, reqs=nil
    s.dependencies.reverse_each do |d|
      next if d.type == :development and not @development
      reqs = Gem::List.new Gem::DependencyResolver::DependencyRequest.new(d, act), reqs
    end

    @set.prefetch reqs

    reqs
  end

  ##
  # Proceed with resolution! Returns an array of ActivationRequest objects.

  def resolve
    @conflicts = []

    needed = nil

    @needed.reverse_each do |n|
      request = Gem::DependencyResolver::DependencyRequest.new n, nil

      needed = Gem::List.new request, needed
    end

    res = resolve_for needed, nil

    raise Gem::DependencyResolutionError, res if
      res.kind_of? Gem::DependencyResolver::DependencyConflict

    res.to_a
  end

  ##
  # Finds the State in +states+ that matches the +conflict+ so that we can try
  # other possible sets.
  #
  # If no good candidate is found, the first state is tried.

  def find_conflict_state conflict, states # :nodoc:
    rejected = []

    until states.empty? do
      state = states.pop

      if conflict.for_spec? state.spec
        state.conflicts << [state.spec, conflict]
        return state
      end

      rejected << state
    end

    return rejected.shift
  ensure
    rejected = rejected.concat states
    states.replace rejected
  end

  ##
  # Extracts the specifications that may be able to fulfill +dependency+ and
  # returns those that match the local platform and all those that match.

  def find_possible dependency # :nodoc:
    all = @set.find_all dependency
    matching_platform = select_local_platforms all

    return matching_platform, all
  end

  def handle_conflict(dep, existing)
    # There is a conflict! We return the conflict object which will be seen by
    # the caller and be handled at the right level.

    # If the existing activation indicates that there are other possibles for
    # it, then issue the conflict on the dependency for the activation itself.
    # Otherwise, issue it on the requester's request itself.
    if existing.others_possible? or existing.request.requester.nil? then
      conflict =
        Gem::DependencyResolver::DependencyConflict.new dep, existing
    else
      depreq = existing.request.requester.request
      conflict =
        Gem::DependencyResolver::DependencyConflict.new depreq, existing, dep
    end

    @conflicts << conflict unless @conflicts.include? conflict

    return conflict
  end

  # Contains the state for attempting activation of a set of possible specs.
  # +needed+ is a Gem::List of DependencyRequest objects that, well, need
  # to be satisfied.
  # +specs+ is the List of ActivationRequest that are being tested.
  # +dep+ is the DependencyRequest that was used to generate this state.
  # +spec+ is the Specification for this state.
  # +possible+ is List of DependencyRequest objects that can be tried to
  # find a  complete set.
  # +conflicts+ is a [DependencyRequest, DependencyConflict] hit tried to
  # activate the state.
  #
  State = Struct.new(:needed, :specs, :dep, :spec, :possibles, :conflicts) do
    def summary # :nodoc:
      nd = needed.map { |s| s.to_s }.sort if nd

      if specs then
        ss = specs.map { |s| s.full_name }.sort
        ss.unshift ss.length
      end

      d = dep.to_s
      d << " from #{dep.requester.full_name}" if dep.requester

      ps = possibles.map { |p| p.full_name }.sort
      ps.unshift ps.length

      cs = conflicts.map do |(s, c)|
        [s.full_name, c.conflicting_dependencies.map { |cd| cd.to_s }]
      end

      { :needed => nd, :specs => ss, :dep => d, :spec => spec.full_name,
        :possibles => ps, :conflicts => cs }
    end
  end

  ##
  # The meat of the algorithm. Given +needed+ DependencyRequest objects and
  # +specs+ being a list to ActivationRequest, calculate a new list of
  # ActivationRequest objects.

  def resolve_for needed, specs
    # The State objects that are used to attempt the activation tree.
    states = []

    while needed
      dep = needed.value
      needed = needed.tail

      # If there is already a spec activated for the requested name...
      if specs && existing = specs.find { |s| dep.name == s.name }
        # then we're done since this new dep matches the existing spec.
        next if dep.matches_spec? existing

        conflict = handle_conflict dep, existing

        state = find_conflict_state conflict, states

        return conflict unless state

        needed, specs = resolve_for_conflict needed, specs, state

        states << state unless state.possibles.empty?

        next
      end

      matching, all = find_possible dep

      case matching.size
      when 0
        resolve_for_zero dep, all
      when 1
        needed, specs =
          resolve_for_single needed, specs, dep, matching
      else
        needed, specs =
          resolve_for_multiple needed, specs, states, dep, matching
      end
    end

    specs
  end

  ##
  # Rewinds +needed+ and +specs+ to a previous state in +state+ for a conflict
  # between +dep+ and +existing+.

  def resolve_for_conflict needed, specs, state # :nodoc:
    # We exhausted the possibles so it's definitely not going to work out,
    # bail out.
    raise Gem::ImpossibleDependenciesError.new state.dep, state.conflicts if
      state.possibles.empty?

    # Retry resolution with this spec and add it's dependencies
    spec, act = activation_request state.dep, state.possibles

    needed = requests spec, act, state.needed
    specs = Gem::List.prepend state.specs, act

    return needed, specs
  end

  ##
  # There are multiple +possible+ specifications for this +dep+.  Updates
  # +needed+, +specs+ and +states+ for further resolution of the +possible+
  # choices.

  def resolve_for_multiple needed, specs, states, dep, possible # :nodoc:
    # Sort them so that we try the highest versions first.
    possible = possible.sort_by do |s|
      [s.source, s.version, s.platform == Gem::Platform::RUBY ? -1 : 1]
    end

    spec, act = activation_request dep, possible

    # We may need to try all of +possible+, so we setup state to unwind back
    # to current +needed+ and +specs+ so we can try another. This is code is
    # what makes conflict resolution possible.
    states << State.new(needed, specs, dep, spec, possible, [])

    needed = requests spec, act, needed
    specs = Gem::List.prepend specs, act

    return needed, specs
  end

  ##
  # Add the spec from the +possible+ list to +specs+ and process the spec's
  # dependencies by adding them to +needed+.

  def resolve_for_single needed, specs, dep, possible # :nodoc:
    spec, act = activation_request dep, possible

    specs = Gem::List.prepend specs, act

    # Put the deps for at the beginning of needed
    # rather than the end to match the depth first
    # searching done by the multiple case code below.
    #
    # This keeps the error messages consistent.
    needed = requests spec, act, needed

    return needed, specs
  end

  ##
  # When there are no possible specifications for +dep+ our work is done.

  def resolve_for_zero dep, platform_mismatch # :nodoc:
    @missing << dep

    unless @soft_missing
      raise Gem::UnsatisfiableDependencyError.new(dep, platform_mismatch)
    end
  end

  ##
  # Returns the gems in +specs+ that match the local platform.

  def select_local_platforms specs # :nodoc:
    specs.select do |spec|
      Gem::Platform.installable? spec
    end
  end

end

require 'rubygems/dependency_resolver/activation_request'
require 'rubygems/dependency_resolver/dependency_conflict'
require 'rubygems/dependency_resolver/dependency_request'

require 'rubygems/dependency_resolver/set'
require 'rubygems/dependency_resolver/api_set'
require 'rubygems/dependency_resolver/composed_set'
require 'rubygems/dependency_resolver/best_set'
require 'rubygems/dependency_resolver/current_set'
require 'rubygems/dependency_resolver/index_set'
require 'rubygems/dependency_resolver/installer_set'
require 'rubygems/dependency_resolver/lock_set'
require 'rubygems/dependency_resolver/vendor_set'

require 'rubygems/dependency_resolver/specification'
require 'rubygems/dependency_resolver/spec_specification'
require 'rubygems/dependency_resolver/api_specification'
require 'rubygems/dependency_resolver/index_specification'
require 'rubygems/dependency_resolver/installed_specification'
require 'rubygems/dependency_resolver/vendor_specification'

