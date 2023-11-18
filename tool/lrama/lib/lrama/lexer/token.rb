module Lrama
  class Lexer
    class Token < Struct.new(:s_value, :alias_name, :location, keyword_init: true)

      attr_accessor :referred

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
    end
  end
end

require 'lrama/lexer/token/char'
require 'lrama/lexer/token/ident'
require 'lrama/lexer/token/parameterizing'
require 'lrama/lexer/token/tag'
require 'lrama/lexer/token/user_code'
