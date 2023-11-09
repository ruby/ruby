module Lrama
  class Lexer
    class Token < Struct.new(:s_value, :alias_name, keyword_init: true)

      attr_accessor :line, :column, :referred

      def to_s
        "#{super} line: #{line}, column: #{column}"
      end

      def referred_by?(string)
        [self.s_value, self.alias_name].include?(string)
      end

      def ==(other)
        self.class == other.class && self.s_value == other.s_value
      end
    end
  end
end

require 'lrama/lexer/token/char'
require 'lrama/lexer/token/ident'
require 'lrama/lexer/token/parameterizing'
require 'lrama/lexer/token/tag'
require 'lrama/lexer/token/user_code'
