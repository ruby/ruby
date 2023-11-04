module Lrama
  class Lexer
    class Token
      class Parameterizing < Token
        def option?
          self.s_value == "?"
        end

        def nonempty_list?
          self.s_value == "+"
        end

        def list?
          self.s_value == "*"
        end
      end
    end
  end
end
