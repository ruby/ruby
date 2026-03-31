# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    class Parameterized
      class Rhs
        attr_accessor :symbols #: Array[Lexer::Token::Base]
        attr_accessor :user_code #: Lexer::Token::UserCode?
        attr_accessor :precedence_sym #: Grammar::Symbol?

        # @rbs () -> void
        def initialize
          @symbols = []
          @user_code = nil
          @precedence_sym = nil
        end

        # @rbs (Grammar::Binding bindings) -> Lexer::Token::UserCode?
        def resolve_user_code(bindings)
          return unless user_code

          resolved = Lexer::Token::UserCode.new(s_value: user_code.s_value, location: user_code.location)
          var_to_arg = {} #: Hash[String, String]
          symbols.each do |sym|
            resolved_sym = bindings.resolve_symbol(sym)
            if resolved_sym != sym
              var_to_arg[sym.s_value] = resolved_sym.s_value
            end
          end

          var_to_arg.each do |var, arg|
            resolved.references.each do |ref|
              if ref.name == var
                ref.name = arg
              end
            end
          end

          return resolved
        end
      end
    end
  end
end
