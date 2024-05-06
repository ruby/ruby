module Lrama
  class Grammar
    class ParameterizingRule
      class Rhs
        attr_accessor :symbols, :user_code, :precedence_sym

        def initialize
          @symbols = []
          @user_code = nil
          @precedence_sym = nil
        end

        def resolve_user_code(bindings)
          return unless user_code

          var_to_arg = {}
          symbols.each do |sym|
            resolved_sym = bindings.resolve_symbol(sym)
            if resolved_sym != sym
              var_to_arg[sym.s_value] = resolved_sym.s_value
            end
          end

          var_to_arg.each do |var, arg|
            user_code.references.each do |ref|
              if ref.name == var
                ref.name = arg
              end
            end
          end

          return user_code
        end
      end
    end
  end
end
