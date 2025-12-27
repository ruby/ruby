# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  # Digraph Algorithm of https://dl.acm.org/doi/pdf/10.1145/69622.357187 (P. 625)
  #
  # Digraph is an algorithm for graph data structure.
  # The algorithm efficiently traverses SCC (Strongly Connected Component) of graph
  # and merges nodes attributes within the same SCC.
  #
  # `compute_read_sets` and `compute_follow_sets` have the same structure.
  # Graph of gotos and attributes of gotos are given then compute propagated attributes for each node.
  #
  # In the case of `compute_read_sets`:
  #
  # * Set of gotos is nodes of graph
  # * `reads_relation` is edges of graph
  # * `direct_read_sets` is nodes attributes
  #
  # In the case of `compute_follow_sets`:
  #
  # * Set of gotos is nodes of graph
  # * `includes_relation` is edges of graph
  # * `read_sets` is nodes attributes
  #
  #
  # @rbs generic X < Object -- Type of a node
  # @rbs generic Y < _Or    -- Type of attribute sets assigned to a node which should support merge operation (#| method)
  class Digraph
    # TODO: rbs-inline 0.11.0 doesn't support instance variables.
    #       Move these type declarations above instance variable definitions, once it's supported.
    #       see: https://github.com/soutaro/rbs-inline/pull/149
    #
    # @rbs!
    #   interface _Or
    #     def |: (self) -> self
    #   end
    #   @sets: Array[X]
    #   @relation: Hash[X, Array[X]]
    #   @base_function: Hash[X, Y]
    #   @stack: Array[X]
    #   @h: Hash[X, (Integer|Float)?]
    #   @result: Hash[X, Y]

    # @rbs sets: Array[X] -- Nodes of graph
    # @rbs relation: Hash[X, Array[X]] -- Edges of graph
    # @rbs base_function: Hash[X, Y] -- Attributes of nodes
    # @rbs return: void
    def initialize(sets, relation, base_function)

      # X in the paper
      @sets = sets

      # R in the paper
      @relation = relation

      # F' in the paper
      @base_function = base_function

      # S in the paper
      @stack = []

      # N in the paper
      @h = Hash.new(0)

      # F in the paper
      @result = {}
    end

    # @rbs () -> Hash[X, Y]
    def compute
      @sets.each do |x|
        next if @h[x] != 0
        traverse(x)
      end

      return @result
    end

    private

    # @rbs (X x) -> void
    def traverse(x)
      @stack.push(x)
      d = @stack.count
      @h[x] = d
      @result[x] = @base_function[x] # F x = F' x

      @relation[x]&.each do |y|
        traverse(y) if @h[y] == 0
        @h[x] = [@h[x], @h[y]].min
        @result[x] |= @result[y] # F x = F x + F y
      end

      if @h[x] == d
        while (z = @stack.pop) do
          @h[z] = Float::INFINITY
          break if z == x
          @result[z] = @result[x] # F (Top of S) = F x
        end
      end
    end
  end
end
