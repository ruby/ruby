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
  # with +needed+ Depedency objects.
  #
  # +set+ is an object that provides where to look for specifications to
  # satisify the Dependencies. This defaults to IndexSet, which will query
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

  def handle_conflict(dep, existing)
    # There is a conflict! We return the conflict
    # object which will be seen by the caller and be
    # handled at the right level.

    # If the existing activation indicates that there
    # are other possibles for it, then issue the conflict
    # on the dep for the activation itself. Otherwise, issue
    # it on the requester's request itself.
    #
    if existing.others_possible?
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
  # +dep+ is the DepedencyRequest that was used to generate this state.
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

        # then we're done since this new dep matches the
        # existing spec.
        next if dep.matches_spec? existing

        conflict = handle_conflict dep, existing

        # Look through the state array and pop State objects
        # until we get back to the State that matches the conflict
        # so that we can try other possible sets.

        i = nil

        until states.empty?
          if conflict.for_spec? states.last.spec
            i = states.last
            i.conflicts << [i.spec, conflict]
            break
          else
            states.pop
          end
        end

        if i
          # We exhausted the possibles so it's definitely not going to
          # work out, bail out.

          if i.possibles.empty?
            raise Gem::ImpossibleDependenciesError.new(i.dep, i.conflicts)
          end

          spec = i.possibles.pop

          # Recursively call #resolve_for with this spec
          # and add it's dependencies into the picture...

          act = Gem::DependencyResolver::ActivationRequest.new spec, i.dep

          needed = requests(spec, act, i.needed)
          specs = Gem::List.prepend(i.specs, act)

          next
        else
          return conflict
        end
      end

      # Get a list of all specs that satisfy dep and platform
      possible = @set.find_all dep
      possible = select_local_platforms possible

      case possible.size
      when 0
        @missing << dep

        unless @soft_missing
          # If there are none, then our work here is done.
          raise Gem::UnsatisfiableDependencyError, dep
        end
      when 1
        # If there is one, then we just add it to specs
        # and process the specs dependencies by adding
        # them to needed.

        spec = possible.first
        act = Gem::DependencyResolver::ActivationRequest.new spec, dep, false

        specs = Gem::List.prepend specs, act

        # Put the deps for at the beginning of needed
        # rather than the end to match the depth first
        # searching done by the multiple case code below.
        #
        # This keeps the error messages consistent.
        needed = requests(spec, act, needed)
      else
        # There are multiple specs for this dep. This is
        # the case that this class is built to handle.

        # Sort them so that we try the highest versions
        # first.
        possible = possible.sort_by do |s|
          [s.source, s.version, s.platform == Gem::Platform::RUBY ? -1 : 1]
        end

        # To figure out which to pick, we keep resolving
        # given each one being activated and if there isn't
        # a conflict, we know we've found a full set.
        #
        # We use an until loop rather than #reverse_each
        # to keep the stack short since we're using a recursive
        # algorithm.
        #
        spec = possible.pop

        # We're may need to try all of +possible+, so we setup
        # state to unwind back to current +needed+ and +specs+
        # so we can try another. This is code is what makes the above
        # code in conflict resolution possible.

        act = Gem::DependencyResolver::ActivationRequest.new spec, dep

        states << State.new(needed, specs, dep, spec, possible, [])

        needed = requests(spec, act, needed)
        specs = Gem::List.prepend(specs, act)
      end
    end

    specs
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

