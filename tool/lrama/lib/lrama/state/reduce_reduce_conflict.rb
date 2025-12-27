# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class State
    class ReduceReduceConflict
      attr_reader :symbols #: Array[Grammar::Symbol]
      attr_reader :reduce1 #: State::Action::Reduce
      attr_reader :reduce2 #: State::Action::Reduce

      # @rbs (symbols: Array[Grammar::Symbol], reduce1: State::Action::Reduce, reduce2: State::Action::Reduce) -> void
      def initialize(symbols:, reduce1:, reduce2:)
        @symbols = symbols
        @reduce1 = reduce1
        @reduce2 = reduce2
      end

      # @rbs () -> :reduce_reduce
      def type
        :reduce_reduce
      end
    end
  end
end
