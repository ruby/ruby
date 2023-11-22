module Lrama
  class Counterexamples
    # s: state
    # itm: item within s
    # l: precise lookahead set
    class Triple < Struct.new(:s, :itm, :l)
      alias :state :s
      alias :item :itm
      alias :precise_lookahead_set :l

      def state_item
        StateItem.new(state, item)
      end

      def inspect
        "#{state.inspect}. #{item.display_name}. #{l.map(&:id).map(&:s_value)}"
      end
      alias :to_s :inspect
    end
  end
end
