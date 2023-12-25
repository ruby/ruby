module Lrama
  class Grammar
    class ParameterizingRuleBuilder
      attr_reader :name, :parameters, :rhs

      def initialize(name, parameters, rhs)
        @name = name
        @parameters = parameters
        @rhs = rhs
        @required_parameters_count = parameters.count
      end

      def build_rules(token, actual_args, rule_counter, lhs_tag, line, rule_builders)
        validate_argument_number!(token)
        lhs = lhs(actual_args)
        @rhs.map do |rhs|
          rhs.build_rules(token, actual_args, parameters, rule_counter, lhs, lhs_tag, line, rule_builders)
        end.flatten
      end

      private

      def validate_argument_number!(token)
        unless @required_parameters_count == token.args.count
          raise "Invalid number of arguments. expect: #{@required_parameters_count} actual: #{token.args.count}"
        end
      end

      def lhs(actual_args)
        Lrama::Lexer::Token::Ident.new(s_value: "#{name}_#{actual_args.map(&:s_value).join('_')}")
      end
    end
  end
end
