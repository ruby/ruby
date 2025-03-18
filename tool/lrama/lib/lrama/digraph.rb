# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  # Algorithm Digraph of https://dl.acm.org/doi/pdf/10.1145/69622.357187 (P. 625)
  #
  # @rbs generic X < Object -- Type of a member of `sets`
  # @rbs generic Y < _Or    -- Type of sets assigned to a member of `sets`
  class Digraph
    # TODO: rbs-inline 0.10.0 doesn't support instance variables.
    #       Move these type declarations above instance variable definitions, once it's supported.
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

    # @rbs sets: Array[X]
    # @rbs relation: Hash[X, Array[X]]
    # @rbs base_function: Hash[X, Y]
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
