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

  ##
  # The meat of the algorithm. Given +needed+ DependencyRequest objects and
  # +specs+ being a list to ActivationRequest, calculate a new list of
  # ActivationRequest objects.

  def resolve_for needed, specs
    while needed
      dep = needed.value
      needed = needed.tail

      # If there is already a spec activated for the requested name...
      if specs && existing = specs.find { |s| dep.name == s.name }

        # then we're done since this new dep matches the
        # existing spec.
        next if dep.matches_spec? existing

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

        # We track the conflicts seen so that we can report them
        # to help the user figure out how to fix the situation.
        conflicts = []

        # To figure out which to pick, we keep resolving
        # given each one being activated and if there isn't
        # a conflict, we know we've found a full set.
        #
        # We use an until loop rather than #reverse_each
        # to keep the stack short since we're using a recursive
        # algorithm.
        #
        until possible.empty?
          s = possible.pop

          # Recursively call #resolve_for with this spec
          # and add it's dependencies into the picture...

          act = Gem::DependencyResolver::ActivationRequest.new s, dep

          try = requests(s, act, needed)

          res = resolve_for try, Gem::List.prepend(specs, act)

          # While trying to resolve these dependencies, there may
          # be a conflict!

          if res.kind_of? Gem::DependencyResolver::DependencyConflict
            # The conflict might be created not by this invocation
            # but rather one up the stack, so if we can't attempt
            # to resolve this conflict (conflict isn't with the spec +s+)
            # then just return it so the caller can try to sort it out.
            return res unless res.for_spec? s

            # Otherwise, this is a conflict that we can attempt to fix
            conflicts << [s, res]

            # Optimization:
            #
            # Because the conflict indicates the dependency that trigger
            # it, we can prune possible based on this new information.
            #
            # This cuts down on the number of iterations needed.
            possible.delete_if { |x| !res.dependency.matches_spec? x }
          else
            # No conflict, return the specs
            return res
          end
        end

        # We tried all possibles and nothing worked, so we let the user
        # know and include as much information about the problem since
        # the user is going to have to take action to fix this.
        raise Gem::ImpossibleDependenciesError.new(dep, conflicts)
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

