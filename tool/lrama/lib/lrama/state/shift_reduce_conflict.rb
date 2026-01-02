# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class State
    class ShiftReduceConflict
      attr_reader :symbols #: Array[Grammar::Symbol]
      attr_reader :shift #: State::Action::Shift
      attr_reader :reduce #: State::Action::Reduce

      # @rbs (symbols: Array[Grammar::Symbol], shift: State::Action::Shift, reduce: State::Action::Reduce) -> void
      def initialize(symbols:, shift:, reduce:)
        @symbols = symbols
        @shift = shift
        @reduce = reduce
      end

      # @rbs () -> :shift_reduce
      def type
        :shift_reduce
      end
    end
  end
end
