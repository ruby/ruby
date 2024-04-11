require 'lrama/lexer/token/char'
require 'lrama/lexer/token/ident'
require 'lrama/lexer/token/instantiate_rule'
require 'lrama/lexer/token/tag'
require 'lrama/lexer/token/user_code'

module Lrama
  class Lexer
    class Token
      attr_reader :s_value, :location
      attr_accessor :alias_name, :referred

      def initialize(s_value:, alias_name: nil, location: nil)
        s_value.freeze
        @s_value = s_value
        @alias_name = alias_name
        @location = location
      end

      def to_s
        "#{super} location: #{location}"
      end

      def referred_by?(string)
        [self.s_value, self.alias_name].compact.include?(string)
      end

      def ==(other)
        self.class == other.class && self.s_value == other.s_value
      end

      def first_line
        location.first_line
      end
      alias :line :first_line

      def first_column
        location.first_column
      end
      alias :column :first_column

      def last_line
        location.last_line
      end

      def last_column
        location.last_column
      end

      def invalid_ref(ref, message)
        location = self.location.partial_location(ref.first_column, ref.last_column)
        raise location.generate_error_message(message)
      end
    end
  end
end
