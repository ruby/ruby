module Lrama
  class State
    class Shift
      attr_reader :next_sym, :next_items
      attr_accessor :not_selected

      def initialize(next_sym, next_items)
        @next_sym = next_sym
        @next_items = next_items
      end
    end
  end
end
