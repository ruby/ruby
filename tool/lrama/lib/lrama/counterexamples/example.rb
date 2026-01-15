# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Counterexamples
    class Example
      # TODO: rbs-inline 0.11.0 doesn't support instance variables.
      #       Move these type declarations above instance variable definitions, once it's supported.
      #       see: https://github.com/soutaro/rbs-inline/pull/149
      #
      # @rbs!
      #   @path1: ::Array[StateItem]
      #   @path2: ::Array[StateItem]
      #   @conflict: State::conflict
      #   @conflict_symbol: Grammar::Symbol
      #   @counterexamples: Counterexamples
      #   @derivations1: Derivation
      #   @derivations2: Derivation

      attr_reader :path1 #: ::Array[StateItem]
      attr_reader :path2 #: ::Array[StateItem]
      attr_reader :conflict #: State::conflict
      attr_reader :conflict_symbol #: Grammar::Symbol

      # path1 is shift conflict when S/R conflict
      # path2 is always reduce conflict
      #
      # @rbs (Array[StateItem]? path1, Array[StateItem]? path2, State::conflict conflict, Grammar::Symbol conflict_symbol, Counterexamples counterexamples) -> void
      def initialize(path1, path2, conflict, conflict_symbol, counterexamples)
        @path1 = path1
        @path2 = path2
        @conflict = conflict
        @conflict_symbol = conflict_symbol
        @counterexamples = counterexamples
      end

      # @rbs () -> (:shift_reduce | :reduce_reduce)
      def type
        @conflict.type
      end

      # @rbs () -> State::Item
      def path1_item
        @path1.last.item
      end

      # @rbs () -> State::Item
      def path2_item
        @path2.last.item
      end

      # @rbs () -> Derivation
      def derivations1
        @derivations1 ||= _derivations(path1)
      end

      # @rbs () -> Derivation
      def derivations2
        @derivations2 ||= _derivations(path2)
      end

      private

      # @rbs (Array[StateItem] state_items) -> Derivation
      def _derivations(state_items)
        derivation = nil #: Derivation
        current = :production
        last_state_item = state_items.last #: StateItem
        lookahead_sym = last_state_item.item.end_of_rule? ? @conflict_symbol : nil

        state_items.reverse_each do |si|
          item = si.item

          case current
          when :production
            case si.type
            when :start
              derivation = Derivation.new(item, derivation)
              current = :start
            when :transition
              derivation = Derivation.new(item, derivation)
              current = :transition
            when :production
              derivation = Derivation.new(item, derivation)
              current = :production
            else
              raise "Unexpected. #{si}"
            end

            if lookahead_sym && item.next_next_sym && item.next_next_sym.first_set.include?(lookahead_sym)
              si2 = @counterexamples.transitions[[si, item.next_sym]]
              derivation2 = find_derivation_for_symbol(si2, lookahead_sym)
              derivation.right = derivation2 # steep:ignore
              lookahead_sym = nil
            end

          when :transition
            case si.type
            when :start
              derivation = Derivation.new(item, derivation)
              current = :start
            when :transition
              # ignore
              current = :transition
            when :production
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

      # @rbs (StateItem state_item, Grammar::Symbol sym) -> Derivation?
      def find_derivation_for_symbol(state_item, sym)
        queue = [] #: Array[Array[StateItem]]
        queue << [state_item]

        while (sis = queue.shift)
          si = sis.last
          next_sym = si.item.next_sym

          if next_sym == sym
            derivation = nil

            sis.reverse_each do |si|
              derivation = Derivation.new(si.item, derivation)
            end

            return derivation
          end

          if next_sym.nterm? && next_sym.first_set.include?(sym)
            @counterexamples.productions[si].each do |next_si|
              next if next_si.item.empty_rule?
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
