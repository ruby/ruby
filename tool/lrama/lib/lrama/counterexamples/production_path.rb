# frozen_string_literal: true

module Lrama
  class Counterexamples
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
