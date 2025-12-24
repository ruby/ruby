# rbs_inline: enabled
# frozen_string_literal: true

require "forwardable"
require_relative "code/destructor_code"
require_relative "code/initial_action_code"
require_relative "code/no_reference_code"
require_relative "code/printer_code"
require_relative "code/rule_action"

module Lrama
  class Grammar
    class Code
      # @rbs!
      #
      #  # delegated
      #  def s_value: -> String
      #  def line: -> Integer
      #  def column: -> Integer
      #  def references: -> Array[Lrama::Grammar::Reference]

      extend Forwardable

      def_delegators "token_code", :s_value, :line, :column, :references

      attr_reader :type #: ::Symbol
      attr_reader :token_code #: Lexer::Token::UserCode

      # @rbs (type: ::Symbol, token_code: Lexer::Token::UserCode) -> void
      def initialize(type:, token_code:)
        @type = type
        @token_code = token_code
      end

      # @rbs (Code other) -> bool
      def ==(other)
        self.class == other.class &&
        self.type == other.type &&
        self.token_code == other.token_code
      end

      # $$, $n, @$, @n are translated to C code
      #
      # @rbs () -> String
      def translated_code
        t_code = s_value.dup

        references.reverse_each do |ref|
          first_column = ref.first_column
          last_column = ref.last_column

          str = reference_to_c(ref)

          t_code[first_column...last_column] = str
        end

        return t_code
      end

      private

      # @rbs (Lrama::Grammar::Reference ref) -> bot
      def reference_to_c(ref)
        raise NotImplementedError.new("#reference_to_c is not implemented")
      end
    end
  end
end
