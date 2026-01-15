# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Lexer
    module Token
      class Int < Base
        # @rbs!
        #   def initialize: (s_value: Integer, ?alias_name: String, ?location: Location) -> void
        #   def s_value: () -> Integer
      end
    end
  end
end
