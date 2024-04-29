module Lrama
  class Grammar
    class ParameterizingRule
      class Resolver
        attr_accessor :rules, :created_lhs_list

        def initialize
          @rules = []
          @created_lhs_list = []
        end

        def add_parameterizing_rule(rule)
          @rules << rule
        end

        def find_rule(token)
          select_rules(@rules, token).last
        end

        def find_inline(token)
          @rules.select { |rule| rule.name == token.s_value && rule.is_inline }.last
        end

        def created_lhs(lhs_s_value)
          @created_lhs_list.reverse.find { |created_lhs| created_lhs.s_value == lhs_s_value }
        end

        private

        def select_rules(rules, token)
          rules = select_not_inline_rules(rules)
          rules = select_rules_by_name(rules, token.rule_name)
          rules = rules.select { |rule| rule.required_parameters_count == token.args_count }
          if rules.empty?
            raise "Invalid number of arguments. `#{token.rule_name}`"
          else
            rules
          end
        end

        def select_not_inline_rules(rules)
          rules.select { |rule| !rule.is_inline }
        end

        def select_rules_by_name(rules, rule_name)
          rules = rules.select { |rule| rule.name == rule_name }
          if rules.empty?
            raise "Parameterizing rule does not exist. `#{rule_name}`"
          else
            rules
          end
        end
      end
    end
  end
end
