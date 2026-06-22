# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    class Parameterized
      class Rule
        attr_reader :name #: String
        attr_reader :parameters #: Array[Lexer::Token::Base]
        attr_reader :rhs #: Array[Rhs]
        attr_reader :required_parameters_count #: Integer
        attr_reader :tag #: Lexer::Token::Tag?

        # @rbs (String name, Array[Lexer::Token::Base] parameters, Array[Rhs] rhs, tag: Lexer::Token::Tag?, is_inline: bool) -> void
        def initialize(name, parameters, rhs, tag: nil, is_inline: false)
          @name = name
          @parameters = parameters
          @rhs = rhs
          @tag = tag
          @is_inline = is_inline
          @required_parameters_count = parameters.count
        end

        # @rbs () -> String
        def to_s
          "#{@name}(#{@parameters.map(&:s_value).join(', ')})"
        end

        # @rbs () -> bool
        def inline?
          @is_inline
        end
      end
    end
  end
end
