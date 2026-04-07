# frozen_string_literal: true

module SyntaxSuggest
  # Lexes the whole source and wraps the tokens in `Token`.
  #
  # Example usage:
  #
  #   tokens = LexAll.new(source: source)
  #   tokens.each do |token|
  #     puts token.line
  #   end
  class LexAll
    include Enumerable

    def initialize(source:)
      @tokens = self.class.lex(source, 1)
      last_token = nil
      @tokens.map! { |elem|
        last_token = Token.new(elem[0].first, elem[1], elem[2], elem[3], last_token)
      }
    end

    def self.lex(source, line_number)
      Prism.lex_compat(source, line: line_number).value.sort_by { |values| values[0] }
    end

    def to_a
      @tokens
    end

    def each
      return @tokens.each unless block_given?
      @tokens.each do |token|
        yield token
      end
    end

    def [](index)
      @tokens[index]
    end

    def last
      @tokens.last
    end
  end
end

require_relative "token"
