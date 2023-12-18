module Lrama
  class Grammar
    class ParameterizingRules
      class Builder
        # Builder for list of general parameterizing rules
        class List < Base

          # program: list(number)
          #
          # =>
          #
          # program: list_number
          # list_number: ε
          # list_number: list_number number
          def build
            validate_argument_number!

            rules = []
            @build_token = Lrama::Lexer::Token::Ident.new(s_value: "list_#{@token.s_value}")
            rules << Rule.new(id: @rule_counter.increment, _lhs: @build_token, _rhs: [], lhs_tag: @lhs_tag, token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules << Rule.new(id: @rule_counter.increment, _lhs: @build_token, _rhs: [@build_token, @token], lhs_tag: @lhs_tag, token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules
          end
        end
      end
    end
  end
end
