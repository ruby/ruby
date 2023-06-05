# frozen_string_literal: true

require_relative "left_right_lex_count"

module SyntaxSuggest
  # Explains syntax errors based on their source
  #
  # example:
  #
  #   source = "def foo; puts 'lol'" # Note missing end
  #   explain ExplainSyntax.new(
  #     code_lines: CodeLine.from_source(source)
  #   ).call
  #   explain.errors.first
  #   # => "Unmatched keyword, missing `end' ?"
  #
  # When the error cannot be determined by lexical counting
  # then ripper is run against the input and the raw ripper
  # errors returned.
  #
  # Example:
  #
  #   source = "1 * " # Note missing a second number
  #   explain ExplainSyntax.new(
  #     code_lines: CodeLine.from_source(source)
  #   ).call
  #   explain.errors.first
  #   # => "syntax error, unexpected end-of-input"
  class ExplainSyntax
    INVERSE = {
      "{" => "}",
      "}" => "{",
      "[" => "]",
      "]" => "[",
      "(" => ")",
      ")" => "(",
      "|" => "|"
    }.freeze

    def initialize(code_lines:)
      @code_lines = code_lines
      @left_right = LeftRightLexCount.new
      @missing = nil
    end

    def call
      @code_lines.each do |line|
        line.lex.each do |lex|
          @left_right.count_lex(lex)
        end
      end

      self
    end

    # Returns an array of missing elements
    #
    # For example this:
    #
    #   ExplainSyntax.new(code_lines: lines).missing
    #   # => ["}"]
    #
    # Would indicate that the source is missing
    # a `}` character in the source code
    def missing
      @missing ||= @left_right.missing
    end

    # Converts a missing string to
    # an human understandable explanation.
    #
    # Example:
    #
    #   explain.why("}")
    #   # => "Unmatched `{', missing `}' ?"
    #
    def why(miss)
      case miss
      when "keyword"
        "Unmatched `end', missing keyword (`do', `def`, `if`, etc.) ?"
      when "end"
        "Unmatched keyword, missing `end' ?"
      else
        inverse = INVERSE.fetch(miss) {
          raise "Unknown explain syntax char or key: #{miss.inspect}"
        }
        "Unmatched `#{inverse}', missing `#{miss}' ?"
      end
    end

    # Returns an array of syntax error messages
    #
    # If no missing pairs are found it falls back
    # on the original ripper error messages
    def errors
      if missing.empty?
        return RipperErrors.new(@code_lines.map(&:original).join).call.errors
      end

      missing.map { |miss| why(miss) }
    end
  end
end
