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
    Gem::DependencyResolver::ComposedSet.new(*sets)
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

    @conflicts    = nil
    @development  = false
    @missing      = []
    @soft_missing = false
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

  def find_conflict_state conflict, states # :nodoc:
    until states.empty? do
      if conflict.for_spec? states.last.spec
        state = states.last
        state.conflicts << [state.spec, conflict]
        return state
      else
        states.pop
      end
    end

    nil
  end

  ##
  # Extracts the specifications that may be able to fulfill +dependency+

  def find_possible dependency # :nodoc:
    possible = @set.find_all dependency
    select_local_platforms possible
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

    @conflicts << conflict

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
  State = Struct.new(:needed, :specs, :dep, :spec, :possibles, :conflicts)

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

        next
      end

      possible = find_possible dep

      case possible.size
      when 0
        resolve_for_zero dep
      when 1
        needed, specs =
          resolve_for_single needed, specs, dep, possible
      else
        needed, specs =
          resolve_for_multiple needed, specs, states, dep, possible
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

    spec = state.possibles.pop

    # Retry resolution with this spec and add it's dependencies
    act = Gem::DependencyResolver::ActivationRequest.new spec, state.dep

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

    # To figure out which to pick, we keep resolving given each one being
    # activated and if there isn't a conflict, we know we've found a full set.
    #
    # We use an until loop rather than reverse_each to keep the stack short
    # since we're using a recursive algorithm.
    spec = possible.pop

    # We may need to try all of +possible+, so we setup state to unwind back
    # to current +needed+ and +specs+ so we can try another. This is code is
    # what makes conflict resolution possible.

    act = Gem::DependencyResolver::ActivationRequest.new spec, dep

    states << State.new(needed, specs, dep, spec, possible, [])

    needed = requests spec, act, needed
    specs = Gem::List.prepend specs, act

    return needed, specs
  end

  ##
  # Add the spec from the +possible+ list to +specs+ and process the spec's
  # dependencies by adding them to +needed+.

  def resolve_for_single needed, specs, dep, possible # :nodoc:
    spec = possible.first
    act = Gem::DependencyResolver::ActivationRequest.new spec, dep, false

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

  def resolve_for_zero dep # :nodoc:
    @missing << dep

    unless @soft_missing
      raise Gem::UnsatisfiableDependencyError, dep
    end
  end

  ##
  # Returns the gems in +specs+ that match the local platform.

  def select_local_platforms specs # :nodoc:
    specs.select do |spec|
      Gem::Platform.match spec.platform
    end
  end

end

require 'rubygems/dependency_resolver/api_set'
require 'rubygems/dependency_resolver/api_specification'
require 'rubygems/dependency_resolver/activation_request'
require 'rubygems/dependency_resolver/composed_set'
require 'rubygems/dependency_resolver/current_set'
require 'rubygems/dependency_resolver/dependency_conflict'
require 'rubygems/dependency_resolver/dependency_request'
require 'rubygems/dependency_resolver/index_set'
require 'rubygems/dependency_resolver/index_specification'
require 'rubygems/dependency_resolver/installed_specification'
require 'rubygems/dependency_resolver/installer_set'
require 'rubygems/dependency_resolver/vendor_set'
require 'rubygems/dependency_resolver/vendor_specification'

