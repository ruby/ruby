# frozen_string_literal: true

module Lrama
  class Grammar
    class Binding
      attr_reader :actual_args, :count

      def initialize(parameterizing_rule, actual_args)
        @parameters = parameterizing_rule.parameters
        @actual_args = actual_args
        @parameter_to_arg = @parameters.zip(actual_args).map do |param, arg|
          [param.s_value, arg]
        end.to_h
      end

      def resolve_symbol(symbol)
        if symbol.is_a?(Lexer::Token::InstantiateRule)
          resolved_args = symbol.args.map { |arg| resolve_symbol(arg) }
          Lrama::Lexer::Token::InstantiateRule.new(s_value: symbol.s_value, location: symbol.location, args: resolved_args, lhs_tag: symbol.lhs_tag)
        else
          parameter_to_arg(symbol) || symbol
        end
      end

      def concatenated_args_str(token)
        "#{token.rule_name}_#{token_to_args_s_values(token).join('_')}"
      end

      private

      def parameter_to_arg(symbol)
        if (arg = @parameter_to_arg[symbol.s_value].dup)
          arg.alias_name = symbol.alias_name
        end
        arg
      end

      def token_to_args_s_values(token)
        token.args.flat_map do |arg|
          resolved = resolve_symbol(arg)
          if resolved.is_a?(Lexer::Token::InstantiateRule)
            [resolved.s_value] + resolved.args.map(&:s_value)
          else
            [resolved.s_value]
          end
        end
      end
    end
  end
end
