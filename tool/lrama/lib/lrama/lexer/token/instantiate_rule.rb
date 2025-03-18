# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Lexer
    class Token
      class InstantiateRule < Token
        attr_reader :args #: Array[Lexer::Token]
        attr_reader :lhs_tag #: Lexer::Token::Tag?

        # @rbs (s_value: String, ?alias_name: String, ?location: Location, ?args: Array[Lexer::Token], ?lhs_tag: Lexer::Token::Tag?) -> void
        def initialize(s_value:, alias_name: nil, location: nil, args: [], lhs_tag: nil)
          super s_value: s_value, alias_name: alias_name, location: location
          @args = args
          @lhs_tag = lhs_tag
        end

        # @rbs () -> String
        def rule_name
          s_value
        end

        # @rbs () -> Integer
        def args_count
          args.count
        end
      end
    end
  end
end
