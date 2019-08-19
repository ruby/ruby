# frozen_string_literal: true

module Bundler::Molinillo
  class DependencyGraph
    # A vertex in a {DependencyGraph} that encapsulates a {#name} and a
    # {#payload}
    class Vertex
      # @return [String] the name of the vertex
      attr_accessor :name

      # @return [Object] the payload the vertex holds
      attr_accessor :payload

      # @return [Array<Object>] the explicit requirements that required
      #   this vertex
      attr_reader :explicit_requirements

      # @return [Boolean] whether the vertex is considered a root vertex
      attr_accessor :root
      alias root? root

      # Initializes a vertex with the given name and payload.
      # @param [String] name see {#name}
      # @param [Object] payload see {#payload}
      def initialize(name, payload)
        @name = name.frozen? ? name : name.dup.freeze
        @payload = payload
        @explicit_requirements = []
        @outgoing_edges = []
        @incoming_edges = []
      end

      # @return [Array<Object>] all of the requirements that required
      #   this vertex
      def requirements
        (incoming_edges.map(&:requirement) + explicit_requirements).uniq
      end

      # @return [Array<Edge>] the edges of {#graph} that have `self` as their
      #   {Edge#origin}
      attr_accessor :outgoing_edges

      # @return [Array<Edge>] the edges of {#graph} that have `self` as their
      #   {Edge#destination}
      attr_accessor :incoming_edges

      # @return [Array<Vertex>] the vertices of {#graph} that have an edge with
      #   `self` as their {Edge#destination}
      def predecessors
        incoming_edges.map(&:origin)
      end

      # @return [Array<Vertex>] the vertices of {#graph} where `self` is a
      #   {#descendent?}
      def recursive_predecessors
        vertices = predecessors
        vertices += Compatibility.flat_map(vertices, &:recursive_predecessors)
        vertices.uniq!
        vertices
      end

      # @return [Array<Vertex>] the vertices of {#graph} that have an edge with
      #   `self` as their {Edge#origin}
      def successors
        outgoing_edges.map(&:destination)
      end

      # @return [Array<Vertex>] the vertices of {#graph} where `self` is an
      #   {#ancestor?}
      def recursive_successors
        vertices = successors
        vertices += Compatibility.flat_map(vertices, &:recursive_successors)
        vertices.uniq!
        vertices
      end

      # @return [String] a string suitable for debugging
      def inspect
        "#{self.class}:#{name}(#{payload.inspect})"
      end

      # @return [Boolean] whether the two vertices are equal, determined
      #   by a recursive traversal of each {Vertex#successors}
      def ==(other)
        return true if equal?(other)
        shallow_eql?(other) &&
          successors.to_set == other.successors.to_set
      end

      # @param  [Vertex] other the other vertex to compare to
      # @return [Boolean] whether the two vertices are equal, determined
      #   solely by {#name} and {#payload} equality
      def shallow_eql?(other)
        return true if equal?(other)
        other &&
          name == other.name &&
          payload == other.payload
      end

      alias eql? ==

      # @return [Fixnum] a hash for the vertex based upon its {#name}
      def hash
        name.hash
      end

      # Is there a path from `self` to `other` following edges in the
      # dependency graph?
      # @return true iff there is a path following edges within this {#graph}
      def path_to?(other)
        _path_to?(other)
      end

      alias descendent? path_to?

      # @param [Vertex] other the vertex to check if there's a path to
      # @param [Set<Vertex>] visited the vertices of {#graph} that have been visited
      # @return [Boolean] whether there is a path to `other` from `self`
      def _path_to?(other, visited = Set.new)
        return false unless visited.add?(self)
        return true if equal?(other)
        successors.any? { |v| v._path_to?(other, visited) }
      end
      protected :_path_to?

      # Is there a path from `other` to `self` following edges in the
      # dependency graph?
      # @return true iff there is a path following edges within this {#graph}
      def ancestor?(other)
        other.path_to?(self)
      end

      alias is_reachable_from? ancestor?
    end
  end
end
