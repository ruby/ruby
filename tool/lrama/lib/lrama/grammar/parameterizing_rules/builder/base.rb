module Lrama
  class Grammar
    class ParameterizingRules
      class Builder
        class Base
          def initialize(token, rule_counter, lhs, user_code, precedence_sym, line)
            @args = token.args
            @token = @args.first
            @rule_counter = rule_counter
            @lhs = lhs
            @user_code = user_code
            @precedence_sym = precedence_sym
            @line = line
            @expected_argument_num = 1
          end

          private

          def validate_argument_number!
            unless @args.count == @expected_argument_num
              raise "Invalid number of arguments. expect: #{@expected_argument_num} actual: #{@args.count}"
            end
          end
        end
      end
    end
  end
end
