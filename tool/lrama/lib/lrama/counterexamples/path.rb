# frozen_string_literal: true

module Lrama
  class Counterexamples
    class Path
      def initialize(from_state_item, to_state_item)
        @from_state_item = from_state_item
        @to_state_item = to_state_item
      end

      def from
        @from_state_item
      end

      def to
        @to_state_item
      end

      def to_s
        "#<Path(#{type})>"
      end
      alias :inspect :to_s

      def type
        raise NotImplementedError
      end
    end
  end
end
