module Lrama
  class Grammar
    class ParameterizingRules
      class Builder
        class List < Base
          def build
            validate_argument_number!

            rules = []
            list_token = Lrama::Lexer::Token::Ident.new(s_value: "list_#{@token.s_value}")
            rules << Rule.new(id: @rule_counter.increment, _lhs: @lhs, _rhs: [list_token], token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules << Rule.new(id: @rule_counter.increment, _lhs: list_token, _rhs: [], token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules << Rule.new(id: @rule_counter.increment, _lhs: list_token, _rhs: [list_token, @token], token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules
          end
        end
      end
    end
  end
end
