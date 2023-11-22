module Lrama
  class Grammar
    class ParameterizingRules
      class Builder
        class SeparatedNonemptyList < Base
          def initialize(token, rule_counter, lhs, user_code, precedence_sym, line)
            super
            @separator = @args[0]
            @token = @args[1]
            @expected_argument_num = 2
          end

          def build
            validate_argument_number!

            rules = []
            separated_list_token = Lrama::Lexer::Token::Ident.new(s_value: "separated_nonempty_list_#{@token.s_value}")
            rules << Rule.new(id: @rule_counter.increment, _lhs: @lhs, _rhs: [separated_list_token], token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules << Rule.new(id: @rule_counter.increment, _lhs: separated_list_token, _rhs: [@token], token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules << Rule.new(id: @rule_counter.increment, _lhs: separated_list_token, _rhs: [separated_list_token, @separator, @token], token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules
          end
        end
      end
    end
  end
end
