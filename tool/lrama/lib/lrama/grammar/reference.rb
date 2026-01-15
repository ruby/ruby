# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    # type: :dollar or :at
    # name: String (e.g. $$, $foo, $expr.right)
    # number: Integer (e.g. $1)
    # index: Integer
    # ex_tag: "$<tag>1" (Optional)
    class Reference < Struct.new(:type, :name, :number, :index, :ex_tag, :first_column, :last_column, keyword_init: true)
      # @rbs!
      #   attr_accessor type: ::Symbol
      #   attr_accessor name: String
      #   attr_accessor number: Integer
      #   attr_accessor index: Integer
      #   attr_accessor ex_tag: Lexer::Token::Base?
      #   attr_accessor first_column: Integer
      #   attr_accessor last_column: Integer
      #
      #   def initialize: (type: ::Symbol, ?name: String, ?number: Integer, ?index: Integer, ?ex_tag: Lexer::Token::Base?, first_column: Integer, last_column: Integer) -> void

      # @rbs () -> (String|Integer)
      def value
        name || number
      end
    end
  end
end
