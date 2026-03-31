# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Counterexamples
    class Triple
      attr_reader :precise_lookahead_set #: Bitmap::bitmap

      alias :l :precise_lookahead_set

      # @rbs (StateItem state_item, Bitmap::bitmap precise_lookahead_set) -> void
      def initialize(state_item, precise_lookahead_set)
        @state_item = state_item
        @precise_lookahead_set = precise_lookahead_set
      end

      # @rbs () -> State
      def state
        @state_item.state
      end
      alias :s :state

      # @rbs () -> State::Item
      def item
        @state_item.item
      end
      alias :itm :item

      # @rbs () -> StateItem
      def state_item
        @state_item
      end

      # @rbs () -> ::String
      def inspect
        "#{state.inspect}. #{item.display_name}. #{l.to_s(2)}"
      end
      alias :to_s :inspect
    end
  end
end
