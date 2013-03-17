require 'rubygems'
require 'rubygems/dependency'
require 'rubygems/exceptions'

require 'uri'
require 'net/http'

module Gem

  # Raised when a DependencyConflict reaches the toplevel.
  # Indicates which dependencies were incompatible.
  #
  class DependencyResolutionError < Gem::Exception
    def initialize(conflict)
      @conflict = conflict
      a, b = conflicting_dependencies

      super "unable to resolve conflicting dependencies '#{a}' and '#{b}'"
    end

    attr_reader :conflict

    def conflicting_dependencies
      @conflict.conflicting_dependencies
    end
  end

  # Raised when a dependency requests a gem for which there is
  # no spec.
  #
  class UnsatisfiableDepedencyError < Gem::Exception
    def initialize(dep)
      super "unable to find any gem matching dependency '#{dep}'"

      @dependency = dep
    end

    attr_reader :dependency
  end

  # Raised when dependencies conflict and create the inability to
  # find a valid possible spec for a request.
  #
  class ImpossibleDependenciesError < Gem::Exception
    def initialize(request, conflicts)
      s = conflicts.size == 1 ? "" : "s"
      super "detected #{conflicts.size} conflict#{s} with dependency '#{request.dependency}'"
      @request = request
      @conflicts = conflicts
    end

    def dependency
      @request.dependency
    end

    attr_reader :conflicts
  end

  # Given a set of Gem::Dependency objects as +needed+ and a way
  # to query the set of available specs via +set+, calculates
  # a set of ActivationRequest objects which indicate all the specs
  # that should be activated to meet the all the requirements.
  #
  class DependencyResolver

    # Represents a specification retrieved via the rubygems.org
    # API. This is used to avoid having to load the full
    # Specification object when all we need is the name, version,
    # and dependencies.
    #
    class APISpecification
      attr_reader :set # :nodoc:

      def initialize(set, api_data)
        @set = set
        @name = api_data[:name]
        @version = Gem::Version.new api_data[:number]
        @dependencies = api_data[:dependencies].map do |name, ver|
          Gem::Dependency.new name, ver.split(/\s*,\s*/)
        end
      end

      attr_reader :name, :version, :dependencies

      def == other # :nodoc:
        self.class === other and
          @set          == other.set and
          @name         == other.name and
          @version      == other.version and
          @dependencies == other.dependencies
      end

      def full_name
        "#{@name}-#{@version}"
      end
    end

    # The global rubygems pool, available via the rubygems.org API.
    # Returns instances of APISpecification.
    #
    class APISet
      def initialize
        @data = Hash.new { |h,k| h[k] = [] }
        @dep_uri = URI 'https://rubygems.org/api/v1/dependencies'
      end

      # Return data for all versions of the gem +name+.
      #
      def versions(name)
        if @data.key?(name)
          return @data[name]
        end

        uri = @dep_uri + "?gems=#{name}"
        str = Gem::RemoteFetcher.fetcher.fetch_path uri

        Marshal.load(str).each do |ver|
          @data[ver[:name]] << ver
        end

        @data[name]
      end

      # Return an array of APISpecification objects matching
      # DependencyRequest +req+.
      #
      def find_all(req)
        res = []

        versions(req.name).each do |ver|
          if req.dependency.match? req.name, ver[:number]
            res << APISpecification.new(self, ver)
          end
        end

        res
      end

      # A hint run by the resolver to allow the Set to fetch
      # data for DependencyRequests +reqs+.
      #
      def prefetch(reqs)
        names = reqs.map { |r| r.dependency.name }
        needed = names.find_all { |d| !@data.key?(d) }

        return if needed.empty?

        uri = @dep_uri + "?gems=#{needed.sort.join ','}"
        str = Gem::RemoteFetcher.fetcher.fetch_path uri

        Marshal.load(str).each do |ver|
          @data[ver[:name]] << ver
        end
      end
    end

    # Represents a possible Specification object returned
    # from IndexSet. Used to delay needed to download full
    # Specification objects when only the +name+ and +version+
    # are needed.
    #
    class IndexSpecification
      def initialize(set, name, version, source, plat)
        @set = set
        @name = name
        @version = version
        @source = source
        @platform = plat

        @spec = nil
      end

      attr_reader :name, :version, :source

      def full_name
        "#{@name}-#{@version}"
      end

      def spec
        @spec ||= @set.load_spec(@name, @version, @source)
      end

      def dependencies
        spec.dependencies
      end
    end

    # The global rubygems pool represented via the traditional
    # source index.
    #
    class IndexSet
      def initialize
        @f = Gem::SpecFetcher.fetcher

        @all = Hash.new { |h,k| h[k] = [] }

        list, _ = @f.available_specs(:released)
        list.each do |uri, specs|
          specs.each do |n|
            @all[n.name] << [uri, n]
          end
        end

        @specs = {}
      end

      # Return an array of IndexSpecification objects matching
      # DependencyRequest +req+.
      #
      def find_all(req)
        res = []

        name = req.dependency.name

        @all[name].each do |uri, n|
          if req.dependency.match? n
            res << IndexSpecification.new(self, n.name, n.version,
                                          uri, n.platform)
          end
        end

        res
      end

      # No prefetching needed since we load the whole index in
      # initially.
      #
      def prefetch(gems)
      end

      # Called from IndexSpecification to get a true Specification
      # object.
      #
      def load_spec(name, ver, source)
        key = "#{name}-#{ver}"
        @specs[key] ||= source.fetch_spec(Gem::NameTuple.new(name, ver))
      end
    end

    # A set which represents the installed gems. Respects
    # all the normal settings that control where to look
    # for installed gems.
    #
    class CurrentSet
      def find_all(req)
        req.dependency.matching_specs
      end

      def prefetch(gems)
      end
    end

    # Create DependencyResolver object which will resolve
    # the tree starting with +needed+ Depedency objects.
    #
    # +set+ is an object that provides where to look for
    # specifications to satisify the Dependencies. This
    # defaults to IndexSet, which will query rubygems.org.
    #
    def initialize(needed, set=IndexSet.new)
      @set = set || IndexSet.new # Allow nil to mean IndexSet
      @needed = needed

      @conflicts = nil
    end

    # Provide a DependencyResolver that queries only against
    # the already installed gems.
    #
    def self.for_current_gems(needed)
      new needed, CurrentSet.new
    end

    # Contains all the conflicts encountered while doing resolution
    #
    attr_reader :conflicts

    # Proceed with resolution! Returns an array of ActivationRequest
    # objects.
    #
    def resolve
      @conflicts = []

      needed = @needed.map { |n| DependencyRequest.new(n, nil) }

      res = resolve_for needed, []

      if res.kind_of? DependencyConflict
        raise DependencyResolutionError.new(res)
      end

      res
    end

    # Used internally to indicate that a dependency conflicted
    # with a spec that would be activated.
    #
    class DependencyConflict
      def initialize(dependency, activated, failed_dep=dependency)
        @dependency = dependency
        @activated = activated
        @failed_dep = failed_dep
      end

      attr_reader :dependency, :activated

      # Return the Specification that listed the dependency
      #
      def requester
        @failed_dep.requester
      end

      def for_spec?(spec)
        @dependency.name == spec.name
      end

      # Return the 2 dependency objects that conflicted
      #
      def conflicting_dependencies
        [@failed_dep.dependency, @activated.request.dependency]
      end
    end

    # Used Internally. Wraps a Depedency object to also track
    # which spec contained the Dependency.
    #
    class DependencyRequest
      def initialize(dep, act)
        @dependency = dep
        @requester = act
      end

      attr_reader :dependency, :requester

      def name
        @dependency.name
      end

      def matches_spec?(spec)
        @dependency.matches_spec? spec
      end

      def to_s
        @dependency.to_s
      end

      def ==(other)
        case other
        when Dependency
          @dependency == other
        when DependencyRequest
          @dependency == other.dep && @requester == other.requester
        else
          false
        end
      end
    end

    # Specifies a Specification object that should be activated.
    # Also contains a dependency that was used to introduce this
    # activation.
    #
    class ActivationRequest
      def initialize(spec, req, others_possible=true)
        @spec = spec
        @request = req
        @others_possible = others_possible
      end

      attr_reader :spec, :request

      # Indicate if this activation is one of a set of possible
      # requests for the same Dependency request.
      #
      def others_possible?
        @others_possible
      end

      # Return the ActivationRequest that contained the dependency
      # that we were activated for.
      #
      def parent
        @request.requester
      end

      def name
        @spec.name
      end

      def full_name
        @spec.full_name
      end

      def version
        @spec.version
      end

      def full_spec
        Gem::Specification === @spec ? @spec : @spec.spec
      end

      def download(path)
        if @spec.respond_to? :source
          source = @spec.source
        else
          source = Gem.sources.first
        end

        Gem.ensure_gem_subdirectories path

        source.download full_spec, path
      end

      def ==(other)
        case other
        when Gem::Specification
          @spec == other
        when ActivationRequest
          @spec == other.spec && @request == other.request
        else
          false
        end
      end

      ##
      # Indicates if the requested gem has already been installed.

      def installed?
        this_spec = full_spec

        Gem::Specification.any? do |s|
          s == this_spec
        end
      end
    end

    def requests(s, act)
      reqs = []
      s.dependencies.each do |d|
        next unless d.type == :runtime
        reqs << DependencyRequest.new(d, act)
      end

      @set.prefetch(reqs)

      reqs
    end

    # The meat of the algorithm. Given +needed+ DependencyRequest objects
    # and +specs+ being a list to ActivationRequest, calculate a new list
    # of ActivationRequest objects.
    #
    def resolve_for(needed, specs)
      until needed.empty?
        dep = needed.shift

        # If there is already a spec activated for the requested name...
        if existing = specs.find { |s| dep.name == s.name }

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
            conflict = DependencyConflict.new(dep, existing)
          else
            depreq = existing.request.requester.request
            conflict = DependencyConflict.new(depreq, existing, dep)
          end
          @conflicts << conflict

          return conflict
        end

        # Get a list of all specs that satisfy dep
        possible = @set.find_all(dep)

        case possible.size
        when 0
          # If there are none, then our work here is done.
          raise UnsatisfiableDepedencyError.new(dep)
        when 1
          # If there is one, then we just add it to specs
          # and process the specs dependencies by adding
          # them to needed.

          spec = possible.first
          act =  ActivationRequest.new(spec, dep, false)

          specs << act

          # Put the deps for at the beginning of needed
          # rather than the end to match the depth first
          # searching done by the multiple case code below.
          #
          # This keeps the error messages consistent.
          needed = requests(spec, act) + needed
        else
          # There are multiple specs for this dep. This is
          # the case that this class is built to handle.

          # Sort them so that we try the highest versions
          # first.
          possible = possible.sort_by { |s| s.version }

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

            act = ActivationRequest.new(s, dep)

            try = requests(s, act) + needed

            res = resolve_for(try, specs + [act])

            # While trying to resolve these dependencies, there may
            # be a conflict!

            if res.kind_of? DependencyConflict
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
          raise ImpossibleDependenciesError.new(dep, conflicts)
        end
      end

      specs
    end
  end
end
