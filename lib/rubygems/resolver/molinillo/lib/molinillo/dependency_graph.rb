# frozen_string_literal: true
require 'set'
require 'tsort'

module Gem::Resolver::Molinillo
  # A directed acyclic graph that is tuned to hold named dependencies
  class DependencyGraph
    include Enumerable

    # Enumerates through the vertices of the graph.
    # @return [Array<Vertex>] The graph's vertices.
    def each
      vertices.values.each { |v| yield v }
    end

    include TSort

    # @visibility private
    alias_method :tsort_each_node, :each

    # @visibility private
    def tsort_each_child(vertex, &block)
      vertex.successors.each(&block)
    end

    # Topologically sorts the given vertices.
    # @param [Enumerable<Vertex>] vertices the vertices to be sorted, which must
    #   all belong to the same graph.
    # @return [Array<Vertex>] The sorted vertices.
    def self.tsort(vertices)
      TSort.tsort(
        lambda { |b| vertices.each(&b) },
        lambda { |v, &b| (v.successors & vertices).each(&b) }
      )
    end

    # A directed edge of a {DependencyGraph}
    # @attr [Vertex] origin The origin of the directed edge
    # @attr [Vertex] destination The destination of the directed edge
    # @attr [Object] requirement The requirement the directed edge represents
    Edge = Struct.new(:origin, :destination, :requirement)

    # @return [{String => Vertex}] the vertices of the dependency graph, keyed
    #   by {Vertex#name}
    attr_reader :vertices

    # Initializes an empty dependency graph
    def initialize
      @vertices = {}
    end

    # Initializes a copy of a {DependencyGraph}, ensuring that all {#vertices}
    # are properly copied.
    # @param [DependencyGraph] other the graph to copy.
    def initialize_copy(other)
      super
      @vertices = {}
      traverse = lambda do |new_v, old_v|
        return if new_v.outgoing_edges.size == old_v.outgoing_edges.size
        old_v.outgoing_edges.each do |edge|
          destination = add_vertex(edge.destination.name, edge.destination.payload)
          add_edge_no_circular(new_v, destination, edge.requirement)
          traverse.call(destination, edge.destination)
        end
      end
      other.vertices.each do |name, vertex|
        new_vertex = add_vertex(name, vertex.payload, vertex.root?)
        new_vertex.explicit_requirements.replace(vertex.explicit_requirements)
        traverse.call(new_vertex, vertex)
      end
    end

    # @return [String] a string suitable for debugging
    def inspect
      "#{self.class}:#{vertices.values.inspect}"
    end

    # @return [Boolean] whether the two dependency graphs are equal, determined
    #   by a recursive traversal of each {#root_vertices} and its
    #   {Vertex#successors}
    def ==(other)
      return false unless other
      vertices.each do |name, vertex|
        other_vertex = other.vertex_named(name)
        return false unless other_vertex
        return false unless other_vertex.successors.map(&:name).to_set == vertex.successors.map(&:name).to_set
      end
    end

    # @param [String] name
    # @param [Object] payload
    # @param [Array<String>] parent_names
    # @param [Object] requirement the requirement that is requiring the child
    # @return [void]
    def add_child_vertex(name, payload, parent_names, requirement)
      vertex = add_vertex(name, payload)
      parent_names.each do |parent_name|
        unless parent_name
          vertex.root = true
          next
        end
        parent_node = vertex_named(parent_name)
        add_edge(parent_node, vertex, requirement)
      end
      vertex
    end

    # Adds a vertex with the given name, or updates the existing one.
    # @param [String] name
    # @param [Object] payload
    # @return [Vertex] the vertex that was added to `self`
    def add_vertex(name, payload, root = false)
      vertex = vertices[name] ||= Vertex.new(name, payload)
      vertex.payload ||= payload
      vertex.root ||= root
      vertex
    end

    # Detaches the {#vertex_named} `name` {Vertex} from the graph, recursively
    # removing any non-root vertices that were orphaned in the process
    # @param [String] name
    # @return [void]
    def detach_vertex_named(name)
      return unless vertex = vertices.delete(name)
      vertex.outgoing_edges.each do |e|
        v = e.destination
        v.incoming_edges.delete(e)
        detach_vertex_named(v.name) unless v.root? || v.predecessors.any?
      end
    end

    # @param [String] name
    # @return [Vertex,nil] the vertex with the given name
    def vertex_named(name)
      vertices[name]
    end

    # @param [String] name
    # @return [Vertex,nil] the root vertex with the given name
    def root_vertex_named(name)
      vertex = vertex_named(name)
      vertex if vertex && vertex.root?
    end

    # Adds a new {Edge} to the dependency graph
    # @param [Vertex] origin
    # @param [Vertex] destination
    # @param [Object] requirement the requirement that this edge represents
    # @return [Edge] the added edge
    def add_edge(origin, destination, requirement)
      if destination.path_to?(origin)
        raise CircularDependencyError.new([origin, destination])
      end
      add_edge_no_circular(origin, destination, requirement)
    end

    private

    # Adds a new {Edge} to the dependency graph without checking for
    # circularity.
    def add_edge_no_circular(origin, destination, requirement)
      edge = Edge.new(origin, destination, requirement)
      origin.outgoing_edges << edge
      destination.incoming_edges << edge
      edge
    end

    # A vertex in a {DependencyGraph} that encapsulates a {#name} and a
    # {#payload}
    class Vertex
      # @return [String] the name of the vertex
      attr_accessor :name

      # @return [Object] the payload the vertex holds
      attr_accessor :payload

      # @return [Arrary<Object>] the explicit requirements that required
      #   this vertex
      attr_reader :explicit_requirements

      # @return [Boolean] whether the vertex is considered a root vertex
      attr_accessor :root
      alias_method :root?, :root

      # Initializes a vertex with the given name and payload.
      # @param [String] name see {#name}
      # @param [Object] payload see {#payload}
      def initialize(name, payload)
        @name = name
        @payload = payload
        @explicit_requirements = []
        @outgoing_edges = []
        @incoming_edges = []
      end

      # @return [Array<Object>] all of the requirements that required
      #   this vertex
      def requirements
        incoming_edges.map(&:requirement) + explicit_requirements
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
        vertices += vertices.map(&:recursive_predecessors).flatten(1)
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
        vertices += vertices.map(&:recursive_successors).flatten(1)
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
        shallow_eql?(other) &&
          successors.to_set == other.successors.to_set
      end

      # @param  [Vertex] other the other vertex to compare to
      # @return [Boolean] whether the two vertices are equal, determined
      #   solely by {#name} and {#payload} equality
      def shallow_eql?(other)
        other &&
          name == other.name &&
          payload == other.payload
      end

      alias_method :eql?, :==

      # @return [Fixnum] a hash for the vertex based upon its {#name}
      def hash
        name.hash
      end

      # Is there a path from `self` to `other` following edges in the
      # dependency graph?
      # @return true iff there is a path following edges within this {#graph}
      def path_to?(other)
        equal?(other) || successors.any? { |v| v.path_to?(other) }
      end

      alias_method :descendent?, :path_to?

      # Is there a path from `other` to `self` following edges in the
      # dependency graph?
      # @return true iff there is a path following edges within this {#graph}
      def ancestor?(other)
        other.path_to?(self)
      end

      alias_method :is_reachable_from?, :ancestor?
    end
  end
end
