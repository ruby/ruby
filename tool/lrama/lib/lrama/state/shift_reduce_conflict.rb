# frozen_string_literal: true

module Lrama
  class State
    class ShiftReduceConflict < Struct.new(:symbols, :shift, :reduce, keyword_init: true)
      def type
        :shift_reduce
      end
    end
  end
end
