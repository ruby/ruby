module Lrama
  class State
    class Reduce
      # https://www.gnu.org/software/bison/manual/html_node/Default-Reductions.html
      attr_reader :item, :look_ahead, :not_selected_symbols
      attr_accessor :default_reduction

      def initialize(item)
        @item = item
        @look_ahead = nil
        @not_selected_symbols = []
      end

      def rule
        @item.rule
      end

      def look_ahead=(look_ahead)
        @look_ahead = look_ahead.freeze
      end

      def add_not_selected_symbol(sym)
        @not_selected_symbols << sym
      end

      def selected_look_ahead
        if @look_ahead
          @look_ahead - @not_selected_symbols
        else
          []
        end
      end
    end
  end
end
