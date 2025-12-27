# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class State
    class Action
      class Shift
        # TODO: rbs-inline 0.11.0 doesn't support instance variables.
        #       Move these type declarations above instance variable definitions, once it's supported.
        #       see: https://github.com/soutaro/rbs-inline/pull/149
        #
        # @rbs!
        #   @from_state: State
        #   @next_sym: Grammar::Symbol
        #   @to_items: Array[Item]
        #   @to_state: State

        attr_reader :from_state #: State
        attr_reader :next_sym #: Grammar::Symbol
        attr_reader :to_items #: Array[Item]
        attr_reader :to_state #: State
        attr_accessor :not_selected #: bool

        # @rbs (State from_state, Grammar::Symbol next_sym, Array[Item] to_items, State to_state) -> void
        def initialize(from_state, next_sym, to_items, to_state)
          @from_state = from_state
          @next_sym = next_sym
          @to_items = to_items
          @to_state = to_state
        end

        # @rbs () -> void
        def clear_conflicts
          @not_selected = nil
        end
      end
    end
  end
end
