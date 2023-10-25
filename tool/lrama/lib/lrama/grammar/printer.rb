module Lrama
  class Grammar
    class Printer < Struct.new(:ident_or_tags, :code, :lineno, keyword_init: true)
      def translated_code(member)
        code.translated_printer_code(member)
      end
    end
  end
end
