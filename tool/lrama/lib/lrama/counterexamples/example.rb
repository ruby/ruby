module Lrama
  class Counterexamples
    class Example
      attr_reader :path1, :path2, :conflict, :conflict_symbol

      # path1 is shift conflict when S/R conflict
      # path2 is always reduce conflict
      def initialize(path1, path2, conflict, conflict_symbol, counterexamples)
        @path1 = path1
        @path2 = path2
        @conflict = conflict
        @conflict_symbol = conflict_symbol
        @counterexamples = counterexamples
      end

      def type
        @conflict.type
      end

      def path1_item
        @path1.last.to.item
      end

      def path2_item
        @path2.last.to.item
      end

      def derivations1
        @derivations1 ||= _derivations(path1)
      end

      def derivations2
        @derivations2 ||= _derivations(path2)
      end

      private

      def _derivations(paths)
        derivation = nil
        current = :production
        lookahead_sym = paths.last.to.item.end_of_rule? ? @conflict_symbol : nil

        paths.reverse.each do |path|
          item = path.to.item

          case current
          when :production
            case path
            when StartPath
              derivation = Derivation.new(item, derivation)
              current = :start
            when TransitionPath
              derivation = Derivation.new(item, derivation)
              current = :transition
            when ProductionPath
              derivation = Derivation.new(item, derivation)
              current = :production
            end

            if lookahead_sym && item.next_next_sym && item.next_next_sym.first_set.include?(lookahead_sym)
              state_item = @counterexamples.transitions[[path.to, item.next_sym]]
              derivation2 = find_derivation_for_symbol(state_item, lookahead_sym)
              derivation.right = derivation2
              lookahead_sym = nil
            end

          when :transition
            case path
            when StartPath
              derivation = Derivation.new(item, derivation)
              current = :start
            when TransitionPath
              # ignore
              current = :transition
            when ProductionPath
              # ignore
              current = :production
            end
          else
            raise "BUG: Unknown #{current}"
          end

          break if current == :start
        end

        derivation
      end

      def find_derivation_for_symbol(state_item, sym)
        queue = []
        queue << [state_item]

        while (sis = queue.shift)
          si = sis.last
          next_sym = si.item.next_sym

          if next_sym == sym
            derivation = nil

            sis.reverse.each do |si|
              derivation = Derivation.new(si.item, derivation)
            end

            return derivation
          end

          if next_sym.nterm? && next_sym.first_set.include?(sym)
            @counterexamples.productions[si].each do |next_item|
              next if next_item.empty_rule?
              next_si = StateItem.new(si.state, next_item)
              next if sis.include?(next_si)
              queue << (sis + [next_si])
            end

            if next_sym.nullable
              next_si = @counterexamples.transitions[[si, next_sym]]
              queue << (sis + [next_si])
            end
          end
        end
      end
    end
  end
end
