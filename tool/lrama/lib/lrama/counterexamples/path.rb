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
    end

    class StartPath < Path
      def initialize(to_state_item)
        super nil, to_state_item
      end

      def type
        :start
      end

      def transition?
        false
      end

      def production?
        false
      end
    end

    class TransitionPath < Path
      def type
        :transition
      end

      def transition?
        true
      end

      def production?
        false
      end
    end

    class ProductionPath < Path
      def type
        :production
      end

      def transition?
        false
      end

      def production?
        true
      end
    end
  end
end
