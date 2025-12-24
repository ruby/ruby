# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    class Counter
      # TODO: rbs-inline 0.11.0 doesn't support instance variables.
      #       Move these type declarations above instance variable definitions, once it's supported.
      #       see: https://github.com/soutaro/rbs-inline/pull/149
      #
      # @rbs!
      #   @number: Integer

      # @rbs (Integer number) -> void
      def initialize(number)
        @number = number
      end

      # @rbs () -> Integer
      def increment
        n = @number
        @number += 1
        n
      end
    end
  end
end
