# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    class ErrorToken
      attr_reader :ident_or_tags #: Array[Lexer::Token::Ident | Lexer::Token::Tag]
      attr_reader :token_code #: Lexer::Token::UserCode
      attr_reader :lineno #: Integer

      # @rbs (ident_or_tags: Array[Lexer::Token::Ident|Lexer::Token::Tag], token_code: Lexer::Token::UserCode, lineno: Integer) -> void
      def initialize(ident_or_tags:, token_code:, lineno:)
        @ident_or_tags = ident_or_tags
        @token_code = token_code
        @lineno = lineno
      end

      # @rbs (Lexer::Token::Tag tag) -> String
      def translated_code(tag)
        Code::PrinterCode.new(type: :error_token, token_code: token_code, tag: tag).translated_code
      end
    end
  end
end
