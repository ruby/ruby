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

      private

      def parameter_to_arg(symbol)
        if (arg = @parameter_to_arg[symbol.s_value].dup)
          arg.alias_name = symbol.alias_name
        end
        arg
      end
    end
  end
end
