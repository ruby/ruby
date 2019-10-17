# frozen_string_literal: true
module Gem::Resolver::Molinillo
  # An error that occurred during the resolution process
  class ResolverError < StandardError; end

  # An error caused by searching for a dependency that is completely unknown,
  # i.e. has no versions available whatsoever.
  class NoSuchDependencyError < ResolverError
    # @return [Object] the dependency that could not be found
    attr_accessor :dependency

    # @return [Array<Object>] the specifications that depended upon {#dependency}
    attr_accessor :required_by

    # Initializes a new error with the given missing dependency.
    # @param [Object] dependency @see {#dependency}
    # @param [Array<Object>] required_by @see {#required_by}
    def initialize(dependency, required_by = [])
      @dependency = dependency
      @required_by = required_by
      super()
    end

    # The error message for the missing dependency, including the specifications
    # that had this dependency.
    def message
      sources = required_by.map { |r| "`#{r}`" }.join(' and ')
      message = "Unable to find a specification for `#{dependency}`"
      message += " depended upon by #{sources}" unless sources.empty?
      message
    end
  end

  # An error caused by attempting to fulfil a dependency that was circular
  #
  # @note This exception will be thrown iff a {Vertex} is added to a
  #   {DependencyGraph} that has a {DependencyGraph::Vertex#path_to?} an
  #   existing {DependencyGraph::Vertex}
  class CircularDependencyError < ResolverError
    # [Set<Object>] the dependencies responsible for causing the error
    attr_reader :dependencies

    # Initializes a new error with the given circular vertices.
    # @param [Array<DependencyGraph::Vertex>] nodes the nodes in the dependency
    #   that caused the error
    def initialize(nodes)
      super "There is a circular dependency between #{nodes.map(&:name).join(' and ')}"
      @dependencies = nodes.map(&:payload).to_set
    end
  end

  # An error caused by conflicts in version
  class VersionConflict < ResolverError
    # @return [{String => Resolution::Conflict}] the conflicts that caused
    #   resolution to fail
    attr_reader :conflicts

    # Initializes a new error with the given version conflicts.
    # @param [{String => Resolution::Conflict}] conflicts see {#conflicts}
    def initialize(conflicts)
      pairs = []
      conflicts.values.flatten.map(&:requirements).flatten.each do |conflicting|
        conflicting.each do |source, conflict_requirements|
          conflict_requirements.each do |c|
            pairs << [c, source]
          end
        end
      end

      super "Unable to satisfy the following requirements:\n\n" \
        "#{pairs.map { |r, d| "- `#{r}` required by `#{d}`" }.join("\n")}"
      @conflicts = conflicts
    end
  end
end
