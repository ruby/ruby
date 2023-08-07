# Symbol is both of nterm and term
# `number` is both for nterm and term
# `token_id` is tokentype for term, internal sequence number for nterm
#
# TODO: Add validation for ASCII code range for Token::Char

module Lrama
  class Grammar
    class Symbol < Struct.new(:id, :alias_name, :number, :tag, :term, :token_id, :nullable, :precedence, :printer, :error_token, keyword_init: true)
      attr_writer :eof_symbol, :error_symbol, :undef_symbol, :accept_symbol

      def term?
        term
      end

      def nterm?
        !term
      end

      def eof_symbol?
        !!@eof_symbol
      end

      def error_symbol?
        !!@error_symbol
      end

      def undef_symbol?
        !!@undef_symbol
      end

      def accept_symbol?
        !!@accept_symbol
      end

      def display_name
        if alias_name
          alias_name
        else
          id.s_value
        end
      end

      # name for yysymbol_kind_t
      #
      # See: b4_symbol_kind_base
      def enum_name
        case
        when accept_symbol?
          name = "YYACCEPT"
        when eof_symbol?
          name = "YYEOF"
        when term? && id.type == Token::Char
          if alias_name
            name = number.to_s + alias_name
          else
            name = number.to_s + id.s_value
          end
        when term? && id.type == Token::Ident
          name = id.s_value
        when nterm? && (id.s_value.include?("$") || id.s_value.include?("@"))
          name = number.to_s + id.s_value
        when nterm?
          name = id.s_value
        else
          raise "Unexpected #{self}"
        end

        "YYSYMBOL_" + name.gsub(/[^a-zA-Z_0-9]+/, "_")
      end

      # comment for yysymbol_kind_t
      def comment
        case
        when accept_symbol?
          # YYSYMBOL_YYACCEPT
          id.s_value
        when eof_symbol?
          # YYEOF
          alias_name
        when (term? && 0 < token_id && token_id < 128)
          # YYSYMBOL_3_backslash_, YYSYMBOL_14_
          alias_name || id.s_value
        when id.s_value.include?("$") || id.s_value.include?("@")
          # YYSYMBOL_21_1
          id.s_value
        else
          # YYSYMBOL_keyword_class, YYSYMBOL_strings_1
          alias_name || id.s_value
        end
      end
    end
  end
end
