module Lrama
  class Grammar
    class ParameterizingRules
      class Builder
        # Base class for parameterizing rules builder
        class Base
          attr_reader :build_token

          def initialize(token, rule_counter, lhs_tag, user_code, precedence_sym, line)
            @args = token.args
            @token = @args.first
            @rule_counter = rule_counter
            @lhs_tag = lhs_tag
            @user_code = user_code
            @precedence_sym = precedence_sym
            @line = line
            @expected_argument_num = 1
            @build_token = nil
          end

          def build
            raise NotImplementedError
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
