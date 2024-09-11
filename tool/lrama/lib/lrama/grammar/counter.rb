# frozen_string_literal: true

module Lrama
  class Grammar
    class Counter
      def initialize(number)
        @number = number
      end

      def increment
        n = @number
        @number += 1
        n
      end
    end
  end
end
