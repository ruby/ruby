module Lrama
  class Grammar
    class ParameterizingRules
      class Builder
        class Option < Base
          def build
            validate_argument_number!

            rules = []
            option_token = Lrama::Lexer::Token::Ident.new(s_value: "option_#{@token.s_value}")
            rules << Rule.new(id: @rule_counter.increment, _lhs: @lhs, _rhs: [option_token], token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules << Rule.new(id: @rule_counter.increment, _lhs: option_token, _rhs: [], token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules << Rule.new(id: @rule_counter.increment, _lhs: option_token, _rhs: [@token], token_code: @ser_code, precedence_sym: @precedence_sym, lineno: @line)
            rules
          end
        end
      end
    end
  end
end
