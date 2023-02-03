# frozen_string_literal: true

module SyntaxSuggest
  # Ripper.lex is not guaranteed to lex the entire source document
  #
  # lex = LexAll.new(source: source)
  # lex.each do |value|
  #   puts value.line
  # end
  class LexAll
    include Enumerable

    def initialize(source:, source_lines: nil)
      @lex = Ripper::Lexer.new(source, "-", 1).parse.sort_by(&:pos)
      lineno = @lex.last.pos.first + 1
      source_lines ||= source.lines
      last_lineno = source_lines.length

      until lineno >= last_lineno
        lines = source_lines[lineno..-1]

        @lex.concat(
          Ripper::Lexer.new(lines.join, "-", lineno + 1).parse.sort_by(&:pos)
        )
        lineno = @lex.last.pos.first + 1
      end

      last_lex = nil
      @lex.map! { |elem|
        last_lex = LexValue.new(elem.pos.first, elem.event, elem.tok, elem.state, last_lex)
      }
    end

    def to_a
      @lex
    end

    def each
      return @lex.each unless block_given?
      @lex.each do |x|
        yield x
      end
    end

    def [](index)
      @lex[index]
    end

    def last
      @lex.last
    end
  end
end

require_relative "lex_value"
