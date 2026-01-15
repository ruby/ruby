# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    class Binding
      # @rbs @actual_args: Array[Lexer::Token::Base]
      # @rbs @param_to_arg: Hash[String, Lexer::Token::Base]

      # @rbs (Array[Lexer::Token::Base] params, Array[Lexer::Token::Base] actual_args) -> void
      def initialize(params, actual_args)
        @actual_args = actual_args
        @param_to_arg = build_param_to_arg(params, @actual_args)
      end

      # @rbs (Lexer::Token::Base sym) -> Lexer::Token::Base
      def resolve_symbol(sym)
        return create_instantiate_rule(sym) if sym.is_a?(Lexer::Token::InstantiateRule)
        find_arg_for_param(sym)
      end

      # @rbs (Lexer::Token::InstantiateRule token) -> String
      def concatenated_args_str(token)
        "#{token.rule_name}_#{format_args(token)}"
      end

      private

      # @rbs (Lexer::Token::InstantiateRule sym) -> Lexer::Token::InstantiateRule
      def create_instantiate_rule(sym)
        Lrama::Lexer::Token::InstantiateRule.new(
          s_value: sym.s_value,
          location: sym.location,
          args: resolve_args(sym.args),
          lhs_tag: sym.lhs_tag
        )
      end

      # @rbs (Array[Lexer::Token::Base]) -> Array[Lexer::Token::Base]
      def resolve_args(args)
        args.map { |arg| resolve_symbol(arg) }
      end

      # @rbs (Lexer::Token::Base sym) -> Lexer::Token::Base
      def find_arg_for_param(sym)
        if (arg = @param_to_arg[sym.s_value]&.dup)
          arg.alias_name = sym.alias_name
          arg
        else
          sym
        end
      end

      # @rbs (Array[Lexer::Token::Base] params, Array[Lexer::Token::Base] actual_args) -> Hash[String, Lexer::Token::Base?]
      def build_param_to_arg(params, actual_args)
        params.zip(actual_args).map do |param, arg|
          [param.s_value, arg]
        end.to_h
      end

      # @rbs (Lexer::Token::InstantiateRule token) -> String
      def format_args(token)
        token_to_args_s_values(token).join('_')
      end

      # @rbs (Lexer::Token::InstantiateRule token) -> Array[String]
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
