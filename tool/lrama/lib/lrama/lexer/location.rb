module Lrama
  class Lexer
    class Location
      attr_reader :first_line, :first_column, :last_line, :last_column

      def initialize(first_line:, first_column:, last_line:, last_column:)
        @first_line = first_line
        @first_column = first_column
        @last_line = last_line
        @last_column = last_column
      end

      def ==(other)
        self.class == other.class &&
        self.first_line == other.first_line &&
        self.first_column == other.first_column &&
        self.last_line == other.last_line &&
        self.last_column == other.last_column
      end
    end
  end
end
