# rbs_inline: enabled
# frozen_string_literal: true

require_relative 'token/char'
require_relative 'token/ident'
require_relative 'token/instantiate_rule'
require_relative 'token/tag'
require_relative 'token/user_code'

module Lrama
  class Lexer
    class Token
      attr_reader :s_value #: String
      attr_reader :location #: Location
      attr_accessor :alias_name #: String
      attr_accessor :referred #: bool

      # @rbs (s_value: String, ?alias_name: String, ?location: Location) -> void
      def initialize(s_value:, alias_name: nil, location: nil)
        s_value.freeze
        @s_value = s_value
        @alias_name = alias_name
        @location = location
      end

      # @rbs () -> String
      def to_s
        "value: `#{s_value}`, location: #{location}"
      end

      # @rbs (String string) -> bool
      def referred_by?(string)
        [self.s_value, self.alias_name].compact.include?(string)
      end

      # @rbs (Token other) -> bool
      def ==(other)
        self.class == other.class && self.s_value == other.s_value
      end

      # @rbs () -> Integer
      def first_line
        location.first_line
      end
      alias :line :first_line

      # @rbs () -> Integer
      def first_column
        location.first_column
      end
      alias :column :first_column

      # @rbs () -> Integer
      def last_line
        location.last_line
      end

      # @rbs () -> Integer
      def last_column
        location.last_column
      end

      # @rbs (Lrama::Grammar::Reference ref, String message) -> bot
      def invalid_ref(ref, message)
        location = self.location.partial_location(ref.first_column, ref.last_column)
        raise location.generate_error_message(message)
      end
    end
  end
end
