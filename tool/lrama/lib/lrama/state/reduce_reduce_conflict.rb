module Lrama
  class State
    class ReduceReduceConflict < Struct.new(:symbols, :reduce1, :reduce2, keyword_init: true)
      def type
        :reduce_reduce
      end
    end
  end
end
