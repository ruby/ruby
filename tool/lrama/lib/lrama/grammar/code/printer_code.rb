# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    class Code
      class PrinterCode < Code
        # TODO: rbs-inline 0.11.0 doesn't support instance variables.
        #       Move these type declarations above instance variable definitions, once it's supported.
        #       see: https://github.com/soutaro/rbs-inline/pull/149
        #
        # @rbs!
        #   @tag: Lexer::Token::Tag

        # @rbs (type: ::Symbol, token_code: Lexer::Token::UserCode, tag: Lexer::Token::Tag) -> void
        def initialize(type:, token_code:, tag:)
          super(type: type, token_code: token_code)
          @tag = tag
        end

        private

        # * ($$) *yyvaluep
        # * (@$) *yylocationp
        # * ($:$) error
        # * ($1) error
        # * (@1) error
        # * ($:1) error
        #
        # @rbs (Reference ref) -> (String | bot)
        def reference_to_c(ref)
          case
          when ref.type == :dollar && ref.name == "$" # $$
            member = @tag.member
            "((*yyvaluep).#{member})"
          when ref.type == :at && ref.name == "$" # @$
            "(*yylocationp)"
          when ref.type == :index && ref.name == "$" # $:$
            raise "$:#{ref.value} can not be used in #{type}."
          when ref.type == :dollar # $n
            raise "$#{ref.value} can not be used in #{type}."
          when ref.type == :at # @n
            raise "@#{ref.value} can not be used in #{type}."
          when ref.type == :index # $:n
            raise "$:#{ref.value} can not be used in #{type}."
          else
            raise "Unexpected. #{self}, #{ref}"
          end
        end
      end
    end
  end
end
