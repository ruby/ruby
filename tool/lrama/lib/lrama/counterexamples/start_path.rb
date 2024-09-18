# frozen_string_literal: true

module Lrama
  class Counterexamples
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
  end
end
