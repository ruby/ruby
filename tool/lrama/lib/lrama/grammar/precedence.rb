# frozen_string_literal: true

module Lrama
  class Grammar
    class Precedence < Struct.new(:type, :precedence, keyword_init: true)
      include Comparable

      def <=>(other)
        self.precedence <=> other.precedence
      end
    end
  end
end
