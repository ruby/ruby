module Lrama
  class Grammar
    class ParameterizingRules
      class Builder
        # Builder for separated nonempty list of general parameterizing rules
        class SeparatedNonemptyList < Base
          def initialize(token, rule_counter, lhs_tag, user_code, precedence_sym, line)
            super
            @separator = @args[0]
            @token = @args[1]
            @expected_argument_num = 2
          end

          # program: separated_nonempty_list(',', number)
          #
          # =>
          #
          # program: separated_nonempty_list_number
          # separated_nonempty_list_number: number
          # separated_nonempty_list_number: separated_nonempty_list_number ',' number
          def build
            validate_argument_number!

            rules = []
            @build_token = Lrama::Lexer::Token::Ident.new(s_value: "separated_nonempty_list_#{@token.s_value}")
            rules << Rule.new(id: @rule_counter.increment, _lhs: @build_token, _rhs: [@token], lhs_tag: @lhs_tag, token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules << Rule.new(id: @rule_counter.increment, _lhs: @build_token, _rhs: [@build_token, @separator, @token], lhs_tag: @lhs_tag, token_code: @user_code, precedence_sym: @precedence_sym, lineno: @line)
            rules
          end
        end
      end
    end
  end
end
