# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Lexer
    class GrammarFile
      class Text < String
        # @rbs () -> String
        def inspect
          length <= 50 ? super : "#{self[0..47]}...".inspect
        end
      end

      attr_reader :path #: String
      attr_reader :text #: String

      # @rbs (String path, String text) -> void
      def initialize(path, text)
        @path = path
        @text = Text.new(text).freeze
      end

      # @rbs () -> String
      def inspect
        "<#{self.class}: @path=#{path}, @text=#{text.inspect}>"
      end

      # @rbs (GrammarFile other) -> bool
      def ==(other)
        self.class == other.class &&
        self.path == other.path
      end

      # @rbs () -> Array[String]
      def lines
        @lines ||= text.split("\n")
      end
    end
  end
end
