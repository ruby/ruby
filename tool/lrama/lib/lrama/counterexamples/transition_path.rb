# frozen_string_literal: true

module Lrama
  class Counterexamples
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
  end
end
