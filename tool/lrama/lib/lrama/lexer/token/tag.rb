# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Lexer
    class Token
      class Tag < Token
        # @rbs () -> String
        def member
          # Omit "<>"
          s_value[1..-2] or raise "Unexpected Tag format (#{s_value})"
        end
      end
    end
  end
end
