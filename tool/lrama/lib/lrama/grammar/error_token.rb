module Lrama
  class Grammar
    class ErrorToken < Struct.new(:ident_or_tags, :code, :lineno, keyword_init: true)
      def translated_code(member)
        code.translated_error_token_code(member)
      end
    end
  end
end
