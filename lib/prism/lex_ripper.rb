# frozen_string_literal: true
# :markup: markdown

require "ripper"

module Prism
  # This is a class that wraps the Ripper lexer to produce almost exactly the
  # same tokens.
  class LexRipper # :nodoc:
    attr_reader :source

    def initialize(source)
      @source = source
    end

    def result
      previous = [] #: [[Integer, Integer], Symbol, String, untyped] | []
      results = [] #: Array[[[Integer, Integer], Symbol, String, untyped]]

      lex(source).each do |token|
        case token[1]
        when :on_sp
          # skip
        when :on_tstring_content
          if previous[1] == :on_tstring_content && (token[2].start_with?("\#$") || token[2].start_with?("\#@"))
            previous[2] << token[2]
          else
            results << token
            previous = token
          end
        when :on_words_sep
          if previous[1] == :on_words_sep
            previous[2] << token[2]
          else
            results << token
            previous = token
          end
        else
          results << token
          previous = token
        end
      end

      results
    end

    private

    if Ripper.method(:lex).parameters.assoc(:keyrest)
      def lex(source)
        Ripper.lex(source, raise_errors: true)
      end
    else
      def lex(source)
        ripper = Ripper::Lexer.new(source)
        ripper.lex.tap do |result|
          raise SyntaxError, ripper.errors.map(&:message).join(' ;') if ripper.errors.any?
        end
      end
    end
  end

  private_constant :LexRipper
end
