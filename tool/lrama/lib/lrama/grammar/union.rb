module Lrama
  class Grammar
    class Union < Struct.new(:code, :lineno, keyword_init: true)
      def braces_less_code
        # Remove braces
        code.s_value[1..-2]
      end
    end
  end
end
