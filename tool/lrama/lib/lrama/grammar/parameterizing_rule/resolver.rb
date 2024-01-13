module Lrama
  class Grammar
    class ParameterizingRule
      class Resolver
        attr_accessor :created_lhs_list

        def initialize
          @rules = []
          @created_lhs_list = []
        end

        def add_parameterizing_rule(rule)
          @rules << rule
        end

        def defined?(token)
          !select_rules(token).empty?
        end

        def find(token)
          select_rules(token).last
        end

        def created_lhs(lhs_s_value)
          @created_lhs_list.select { |created_lhs| created_lhs.s_value == lhs_s_value }.last
        end

        private

        def select_rules(token)
          @rules.select do |rule|
            rule.name == token.rule_name &&
              rule.required_parameters_count == token.args_count
          end
        end
      end
    end
  end
end
