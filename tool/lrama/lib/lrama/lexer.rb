require "strscan"
require "lrama/lexer/token"

module Lrama
  class Lexer
    attr_accessor :status
    attr_accessor :end_symbol

    SYMBOLS = %w(%{ %} %% { } \[ \] : \| ;)
    PERCENT_TOKENS = %w(
      %union
      %token
      %type
      %left
      %right
      %nonassoc
      %expect
      %define
      %require
      %printer
      %lex-param
      %parse-param
      %initial-action
      %precedence
      %prec
      %error-token
    )

    def initialize(text)
      @scanner = StringScanner.new(text)
      @head = @scanner.pos
      @line = 1
      @status = :initial
      @end_symbol = nil
    end

    def next_token
      case @status
      when :initial
        lex_token
      when :c_declaration
        lex_c_code
      end
    end

    def line
      @line
    end

    def column
      @scanner.pos - @head
    end

    def lex_token
      while !@scanner.eos? do
        case
        when @scanner.scan(/\n/)
          newline
        when @scanner.scan(/\s+/)
          # noop
        when @scanner.scan(/\/\*/)
          lex_comment
        when @scanner.scan(/\/\//)
          @scanner.scan_until(/\n/)
          newline
        when @scanner.scan(/%empty/)
          # noop
        else
          break
        end
      end

      @head_line = line
      @head_column = column

      case
      when @scanner.eos?
        return
      when @scanner.scan(/#{SYMBOLS.join('|')}/)
        return [@scanner.matched, @scanner.matched]
      when @scanner.scan(/#{PERCENT_TOKENS.join('|')}/)
        return [@scanner.matched, @scanner.matched]
      when @scanner.scan(/<\w+>/)
        return [:TAG, build_token(type: Token::Tag, s_value: @scanner.matched)]
      when @scanner.scan(/'.'/)
        return [:CHARACTER, build_token(type: Token::Char, s_value: @scanner.matched)]
      when @scanner.scan(/'\\\\'|'\\b'|'\\t'|'\\f'|'\\r'|'\\n'|'\\v'|'\\13'/)
        return [:CHARACTER, build_token(type: Token::Char, s_value: @scanner.matched)]
      when @scanner.scan(/"/)
        return [:STRING, %Q("#{@scanner.scan_until(/"/)})]
      when @scanner.scan(/\d+/)
        return [:INTEGER, Integer(@scanner.matched)]
      when @scanner.scan(/([a-zA-Z_.][-a-zA-Z0-9_.]*)/)
        token = build_token(type: Token::Ident, s_value: @scanner.matched)
        type =
          if @scanner.check(/\s*(\[\s*[a-zA-Z_.][-a-zA-Z0-9_.]*\s*\])?\s*:/)
            :IDENT_COLON
          else
            :IDENTIFIER
          end
        return [type, token]
      else
        raise
      end
    end

    def lex_c_code
      nested = 0
      code = ''
      while !@scanner.eos? do
        case
        when @scanner.scan(/{/)
          code += @scanner.matched
          nested += 1
        when @scanner.scan(/}/)
          if nested == 0 && @end_symbol == '}'
            @scanner.unscan
            return [:C_DECLARATION, build_token(type: Token::User_code, s_value: code, references: [])]
          else
            code += @scanner.matched
            nested -= 1
          end
        when @scanner.check(/#{@end_symbol}/)
          return [:C_DECLARATION, build_token(type: Token::User_code, s_value: code, references: [])]
        when @scanner.scan(/\n/)
          code += @scanner.matched
          newline
        when @scanner.scan(/"/)
          matched = @scanner.scan_until(/"/)
          code += %Q("#{matched})
          @line += matched.count("\n")
        when @scanner.scan(/'/)
          matched = @scanner.scan_until(/'/)
          code += %Q('#{matched})
        else
          code += @scanner.getch
        end
      end
      raise
    end

    private

    def lex_comment
      while !@scanner.eos? do
        case
        when @scanner.scan(/\n/)
          @line += 1
          @head = @scanner.pos + 1
        when @scanner.scan(/\*\//)
          return
        else
          @scanner.getch
        end
      end
    end

    def build_token(type:, s_value:, **options)
      token = Token.new(type: type, s_value: s_value)
      token.line = @head_line
      token.column = @head_column
      options.each do |attr, value|
        token.public_send("#{attr}=", value)
      end

      token
    end

    def newline
      @line += 1
      @head = @scanner.pos + 1
    end
  end
end
