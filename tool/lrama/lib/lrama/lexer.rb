# rbs_inline: enabled
# frozen_string_literal: true

require "strscan"

require_relative "lexer/grammar_file"
require_relative "lexer/location"
require_relative "lexer/token"

module Lrama
  class Lexer
    # @rbs!
    #
    #   type token = lexer_token | c_token
    #
    #   type lexer_token = [String, Token::Token]  |
    #                      [::Symbol, Token::Tag]  |
    #                      [::Symbol, Token::Char] |
    #                      [::Symbol, Token::Str]  |
    #                      [::Symbol, Token::Int]  |
    #                      [::Symbol, Token::Ident]
    #
    #   type c_token = [:C_DECLARATION, Token::UserCode]

    attr_reader :head_line #: Integer
    attr_reader :head_column #: Integer
    attr_reader :line #: Integer
    attr_accessor :status #: :initial | :c_declaration
    attr_accessor :end_symbol #: String?

    SYMBOLS = ['%{', '%}', '%%', '{', '}', '\[', '\]', '\(', '\)', '\,', ':', '\|', ';'].freeze #: Array[String]
    PERCENT_TOKENS = %w(
      %union
      %token
      %type
      %nterm
      %left
      %right
      %nonassoc
      %expect
      %define
      %require
      %printer
      %destructor
      %lex-param
      %parse-param
      %initial-action
      %precedence
      %prec
      %error-token
      %before-reduce
      %after-reduce
      %after-shift-error-token
      %after-shift
      %after-pop-stack
      %empty
      %code
      %rule
      %no-stdlib
      %inline
      %locations
      %categories
      %start
    ).freeze #: Array[String]

    # @rbs (GrammarFile grammar_file) -> void
    def initialize(grammar_file)
      @grammar_file = grammar_file
      @scanner = StringScanner.new(grammar_file.text)
      @head_column = @head = @scanner.pos
      @head_line = @line = 1
      @status = :initial
      @end_symbol = nil
    end

    # @rbs () -> token?
    def next_token
      case @status
      when :initial
        lex_token
      when :c_declaration
        lex_c_code
      end
    end

    # @rbs () -> Integer
    def column
      @scanner.pos - @head
    end

    # @rbs () -> Location
    def location
      Location.new(
        grammar_file: @grammar_file,
        first_line: @head_line, first_column: @head_column,
        last_line: line, last_column: column
      )
    end

    # @rbs () -> lexer_token?
    def lex_token
      until @scanner.eos? do
        case
        when @scanner.scan(/\n/)
          newline
        when @scanner.scan(/\s+/)
          @scanner.matched.count("\n").times { newline }
        when @scanner.scan(/\/\*/)
          lex_comment
        when @scanner.scan(/\/\/.*(?<newline>\n)?/)
          newline if @scanner[:newline]
        else
          break
        end
      end

      reset_first_position

      case
      when @scanner.eos?
        return
      when @scanner.scan(/#{SYMBOLS.join('|')}/)
        return [@scanner.matched, Lrama::Lexer::Token::Token.new(s_value: @scanner.matched, location: location)]
      when @scanner.scan(/#{PERCENT_TOKENS.join('|')}/)
        return [@scanner.matched, Lrama::Lexer::Token::Token.new(s_value: @scanner.matched, location: location)]
      when @scanner.scan(/[\?\+\*]/)
        return [@scanner.matched, Lrama::Lexer::Token::Token.new(s_value: @scanner.matched, location: location)]
      when @scanner.scan(/<\w+>/)
        return [:TAG, Lrama::Lexer::Token::Tag.new(s_value: @scanner.matched, location: location)]
      when @scanner.scan(/'.'/)
        return [:CHARACTER, Lrama::Lexer::Token::Char.new(s_value: @scanner.matched, location: location)]
      when @scanner.scan(/'\\\\'|'\\b'|'\\t'|'\\f'|'\\r'|'\\n'|'\\v'|'\\13'/)
        return [:CHARACTER, Lrama::Lexer::Token::Char.new(s_value: @scanner.matched, location: location)]
      when @scanner.scan(/".*?"/)
        return [:STRING, Lrama::Lexer::Token::Str.new(s_value: %Q(#{@scanner.matched}), location: location)]
      when @scanner.scan(/\d+/)
        return [:INTEGER, Lrama::Lexer::Token::Int.new(s_value: Integer(@scanner.matched), location: location)]
      when @scanner.scan(/([a-zA-Z_.][-a-zA-Z0-9_.]*)/)
        token = Lrama::Lexer::Token::Ident.new(s_value: @scanner.matched, location: location)
        type =
          if @scanner.check(/\s*(\[\s*[a-zA-Z_.][-a-zA-Z0-9_.]*\s*\])?\s*:/)
            :IDENT_COLON
          else
            :IDENTIFIER
          end
        return [type, token]
      else
        raise ParseError, location.generate_error_message("Unexpected token") # steep:ignore UnknownConstant
      end
    end

    # @rbs () -> c_token
    def lex_c_code
      nested = 0
      code = +''
      reset_first_position

      until @scanner.eos? do
        case
        when @scanner.scan(/{/)
          code << @scanner.matched
          nested += 1
        when @scanner.scan(/}/)
          if nested == 0 && @end_symbol == '}'
            @scanner.unscan
            return [:C_DECLARATION, Lrama::Lexer::Token::UserCode.new(s_value: code, location: location)]
          else
            code << @scanner.matched
            nested -= 1
          end
        when @scanner.check(/#{@end_symbol}/)
          return [:C_DECLARATION, Lrama::Lexer::Token::UserCode.new(s_value: code, location: location)]
        when @scanner.scan(/\n/)
          code << @scanner.matched
          newline
        when @scanner.scan(/".*?"/)
          code << %Q(#{@scanner.matched})
          @line += @scanner.matched.count("\n")
        when @scanner.scan(/'.*?'/)
          code << %Q(#{@scanner.matched})
        when @scanner.scan(/[^\"'\{\}\n]+/)
          code << @scanner.matched
        when @scanner.scan(/#{Regexp.escape(@end_symbol)}/) # steep:ignore
          code << @scanner.matched
        else
          code << @scanner.getch
        end
      end
      raise ParseError, location.generate_error_message("Unexpected code: #{code}") # steep:ignore UnknownConstant
    end

    private

    # @rbs () -> void
    def lex_comment
      until @scanner.eos? do
        case
        when @scanner.scan_until(/[\s\S]*?\*\//)
          @scanner.matched.count("\n").times { newline }
          return
        when @scanner.scan_until(/\n/)
          newline
        end
      end
    end

    # @rbs () -> void
    def reset_first_position
      @head_line = line
      @head_column = column
    end

    # @rbs () -> void
    def newline
      @line += 1
      @head = @scanner.pos
    end
  end
end
