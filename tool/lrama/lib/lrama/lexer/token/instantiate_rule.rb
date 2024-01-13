module Lrama
  class Lexer
    class Token
      class InstantiateRule < Token
        attr_reader :args, :lhs_tag

        def initialize(s_value:, alias_name: nil, location: nil, args: [], lhs_tag: nil)
          super s_value: s_value, alias_name: alias_name, location: location
          @args = args
          @lhs_tag = lhs_tag
        end

        def rule_name
          s_value
        end

        def args_count
          args.count
        end
      end
    end
  end
end
