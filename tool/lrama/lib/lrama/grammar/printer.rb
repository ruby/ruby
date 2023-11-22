module Lrama
  class Grammar
    class Printer < Struct.new(:ident_or_tags, :token_code, :lineno, keyword_init: true)
      def translated_code(tag)
        Code::PrinterCode.new(type: :printer, token_code: token_code, tag: tag).translated_code
      end
    end
  end
end
