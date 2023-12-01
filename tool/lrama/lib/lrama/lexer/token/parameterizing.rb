module Lrama
  class Lexer
    class Token
      class Parameterizing < Token
        attr_accessor :args

        def initialize(s_value:, alias_name: nil, location: nil, args: [])
          super s_value: s_value, alias_name: alias_name, location: location
          @args = args
        end

        def option?
          %w(option ?).include?(self.s_value)
        end

        def nonempty_list?
          %w(nonempty_list +).include?(self.s_value)
        end

        def list?
          %w(list *).include?(self.s_value)
        end

        def separated_nonempty_list?
          %w(separated_nonempty_list).include?(self.s_value)
        end

        def separated_list?
          %w(separated_list).include?(self.s_value)
        end
      end
    end
  end
end
