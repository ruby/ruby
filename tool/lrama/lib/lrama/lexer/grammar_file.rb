module Lrama
  class Lexer
    class GrammarFile
      attr_reader :path, :text

      def initialize(path, text)
        @path = path
        @text = text.freeze
      end

      def ==(other)
        self.class == other.class &&
        self.path == other.path
      end

      def lines
        @lines ||= text.split("\n")
      end
    end
  end
end
