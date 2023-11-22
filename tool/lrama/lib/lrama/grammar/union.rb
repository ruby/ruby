module Lrama
  class Grammar
    class Union < Struct.new(:code, :lineno, keyword_init: true)
      def braces_less_code
        # Braces is already removed by lexer
        code.s_value
      end
    end
  end
end
