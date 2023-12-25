module Lrama
  class Grammar
    class ParameterizingRuleResolver
      def initialize
        @parameterizing_rule_builders = []
      end

      def add_parameterizing_rule_builder(builder)
        @parameterizing_rule_builders << builder
      end

      def defined?(name)
        !rule_builders(name).empty?
      end

      def build_rules(token, rule_counter, lhs_tag, line)
        builder = rule_builders(token.s_value).last
        raise "Unknown parameterizing rule #{token.s_value} at line #{token.line}" unless builder

        builder.build_rules(token, token.args, rule_counter, lhs_tag, line, @parameterizing_rule_builders)
      end

      private

      def rule_builders(name)
        @parameterizing_rule_builders.select { |builder| builder.name == name }
      end
    end
  end
end
