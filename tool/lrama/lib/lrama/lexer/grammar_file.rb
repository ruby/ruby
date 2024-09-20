# frozen_string_literal: true

module Lrama
  class Lexer
    class GrammarFile
      class Text < String
        def inspect
          length <= 50 ? super : "#{self[0..47]}...".inspect
        end
      end

      attr_reader :path, :text

      def initialize(path, text)
        @path = path
        @text = Text.new(text).freeze
      end

      def inspect
        "<#{self.class}: @path=#{path}, @text=#{text.inspect}>"
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
