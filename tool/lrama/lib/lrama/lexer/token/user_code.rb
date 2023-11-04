module Lrama
  class Lexer
    class Token
      class UserCode < Token
        attr_accessor :references

        def initialize(s_value: nil, alias_name: nil)
          super
          self.references = []
        end
      end
    end
  end
end
