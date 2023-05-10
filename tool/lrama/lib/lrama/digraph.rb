module Lrama
  # Algorithm Digraph of https://dl.acm.org/doi/pdf/10.1145/69622.357187 (P. 625)
  class Digraph
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

    def compute
      @sets.each do |x|
        next if @h[x] != 0
        traverse(x)
      end

      return @result
    end

    private

    def traverse(x)
      @stack.push(x)
      d = @stack.count
      @h[x] = d
      @result[x] = @base_function[x] # F x = F' x

      @relation[x] && @relation[x].each do |y|
        traverse(y) if @h[y] == 0
        @h[x] = [@h[x], @h[y]].min
        @result[x] |= @result[y] # F x = F x + F y
      end

      if @h[x] == d
        while true do
          z = @stack.pop
          @h[z] = Float::INFINITY
          @result[z] = @result[x] # F (Top of S) = F x

          break if z == x
        end
      end
    end
  end
end
