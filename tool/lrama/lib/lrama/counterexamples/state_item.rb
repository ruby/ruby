# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Counterexamples
    class StateItem
      attr_reader :id #: Integer
      attr_reader :state #: State
      attr_reader :item #: State::Item

      # @rbs (Integer id, State state, State::Item item) -> void
      def initialize(id, state, item)
        @id = id
        @state = state
        @item = item
      end

      # @rbs () -> (:start | :transition | :production)
      def type
        case
        when item.start_item?
          :start
        when item.beginning_of_rule?
          :production
        else
          :transition
        end
      end
    end
  end
end
