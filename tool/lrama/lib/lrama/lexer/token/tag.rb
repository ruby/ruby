module Lrama
  class Lexer
    class Token
      class Tag < Token
        # Omit "<>"
        def member
          s_value[1..-2] or raise "Unexpected Tag format (#{s_value})"
        end
      end
    end
  end
end
