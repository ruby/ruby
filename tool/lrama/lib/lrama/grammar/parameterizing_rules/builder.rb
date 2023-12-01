require 'lrama/grammar/parameterizing_rules/builder/base'
require 'lrama/grammar/parameterizing_rules/builder/list'
require 'lrama/grammar/parameterizing_rules/builder/nonempty_list'
require 'lrama/grammar/parameterizing_rules/builder/option'
require 'lrama/grammar/parameterizing_rules/builder/separated_nonempty_list'
require 'lrama/grammar/parameterizing_rules/builder/separated_list'

module Lrama
  class Grammar
    class ParameterizingRules
      # Builder for parameterizing rules
      class Builder
        RULES = {
          option: Lrama::Grammar::ParameterizingRules::Builder::Option,
          "?": Lrama::Grammar::ParameterizingRules::Builder::Option,
          nonempty_list: Lrama::Grammar::ParameterizingRules::Builder::NonemptyList,
          "+": Lrama::Grammar::ParameterizingRules::Builder::NonemptyList,
          list: Lrama::Grammar::ParameterizingRules::Builder::List,
          "*": Lrama::Grammar::ParameterizingRules::Builder::List,
          separated_nonempty_list: Lrama::Grammar::ParameterizingRules::Builder::SeparatedNonemptyList,
          separated_list: Lrama::Grammar::ParameterizingRules::Builder::SeparatedList,
        }

        def initialize(token, rule_counter, lhs_tag, user_code, precedence_sym, line)
          @token = token
          @key = token.s_value.to_sym
          @rule_counter = rule_counter
          @lhs_tag = lhs_tag
          @user_code = user_code
          @precedence_sym = precedence_sym
          @line = line
          @builder = nil
        end

        def build
          create_builder
          @builder.build
        end

        def build_token
          create_builder
          @builder.build_token
        end

        private

        def create_builder
          unless @builder
            validate_key!
            @builder = RULES[@key].new(@token, @rule_counter, @lhs_tag, @user_code, @precedence_sym, @line)
          end
        end

        def validate_key!
          raise "Parameterizing rule does not exist. `#{@key}`" unless RULES.key?(@key)
        end
      end
    end
  end
end
