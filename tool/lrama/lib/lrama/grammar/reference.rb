# type: :dollar or :at
# ex_tag: "$<tag>1" (Optional)

module Lrama
  class Grammar
    class Reference < Struct.new(:type, :value, :ex_tag, :first_column, :last_column, :referring_symbol, :position_in_rhs, keyword_init: true)
      def tag
        if ex_tag
          ex_tag
        else
          # FIXME: Remove this class check
          if referring_symbol.is_a?(Symbol)
            referring_symbol.tag
          else
            # Lrama::Lexer::Token (User_code) case
            nil
          end
        end
      end
    end
  end
end
