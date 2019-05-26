# frozen_string_literal: true
require 'reline'
require 'ripper'

module IRB # :nodoc:
  module Color
    CLEAR     = 0
    BOLD      = 1
    UNDERLINE = 4
    RED       = 31
    GREEN     = 32
    YELLOW    = 33
    BLUE      = 34
    MAGENTA   = 35
    CYAN      = 36

    TOKEN_KEYWORDS = {
      on_kw: ['nil', 'self', 'true', 'false', '__FILE__', '__LINE__'],
      on_const: ['ENV'],
    }

    begin
      TOKEN_SEQ_EXPRS = {
        on_backtick:        [[RED],                   [Ripper::EXPR_BEG]],
        on_CHAR:            [[BLUE, BOLD],            [Ripper::EXPR_END]],
        on_const:           [[BLUE, BOLD, UNDERLINE], [Ripper::EXPR_ARG, Ripper::EXPR_CMDARG, Ripper::EXPR_ENDFN]],
        on_embexpr_beg:     [[RED],                   [Ripper::EXPR_BEG, Ripper::EXPR_END, Ripper::EXPR_CMDARG, Ripper::EXPR_FNAME, Ripper::EXPR_ARG]],
        on_embexpr_end:     [[RED],                   [Ripper::EXPR_BEG, Ripper::EXPR_END, Ripper::EXPR_CMDARG, Ripper::EXPR_ENDFN, Ripper::EXPR_ARG]],
        on_embvar:          [[RED],                   [Ripper::EXPR_BEG]],
        on_heredoc_beg:     [[RED],                   [Ripper::EXPR_BEG]],
        on_heredoc_end:     [[RED],                   [Ripper::EXPR_BEG]],
        on_ident:           [[BLUE, BOLD],            [Ripper::EXPR_ENDFN]],
        on_int:             [[BLUE, BOLD],            [Ripper::EXPR_END]],
        on_float:           [[MAGENTA, BOLD],         [Ripper::EXPR_END]],
        on_kw:              [[GREEN],                 [Ripper::EXPR_ARG, Ripper::EXPR_CLASS, Ripper::EXPR_BEG, Ripper::EXPR_END, Ripper::EXPR_FNAME, Ripper::EXPR_MID]],
        on_label:           [[MAGENTA],               [Ripper::EXPR_LABELED]],
        on_label_end:       [[RED],                   [Ripper::EXPR_BEG]],
        on_qwords_beg:      [[RED],                   [Ripper::EXPR_BEG, Ripper::EXPR_CMDARG]],
        on_qsymbols_beg:    [[RED],                   [Ripper::EXPR_BEG, Ripper::EXPR_CMDARG]],
        on_regexp_beg:      [[RED, BOLD],             [Ripper::EXPR_BEG]],
        on_regexp_end:      [[RED, BOLD],             [Ripper::EXPR_BEG]],
        on_symbeg:          [[YELLOW],                [Ripper::EXPR_FNAME]],
        on_tstring_beg:     [[RED],                   [Ripper::EXPR_BEG, Ripper::EXPR_END, Ripper::EXPR_ARG, Ripper::EXPR_CMDARG]],
        on_tstring_content: [[RED],                   [Ripper::EXPR_BEG, Ripper::EXPR_END, Ripper::EXPR_ARG, Ripper::EXPR_CMDARG, Ripper::EXPR_FNAME]],
        on_tstring_end:     [[RED],                   [Ripper::EXPR_END]],
        on_words_beg:       [[RED],                   [Ripper::EXPR_BEG]],
      }
    rescue NameError
      TOKEN_SEQ_EXPRS = {}
    end

    class << self
      def colorable?
        $stdout.tty? && (/mswin|mingw/ =~ RUBY_PLATFORM || (ENV.key?('TERM') && ENV['TERM'] != 'dumb'))
      end

      def inspect_colorable?(obj)
        case obj
        when String, Symbol, Regexp, Integer, Float, FalseClass, TrueClass, NilClass
          true
        when Hash
          obj.all? { |k, v| inspect_colorable?(k) && inspect_colorable?(v) }
        when Array
          obj.all? { |o| inspect_colorable?(o) }
        when Range
          inspect_colorable?(obj.begin) && inspect_colorable?(obj.end)
        when Module
          !obj.name.nil?
        else
          false
        end
      end

      def clear
        return '' unless colorable?
        "\e[#{CLEAR}m"
      end

      def colorize(text, seq)
        return text unless colorable?
        "#{seq.map { |s| "\e[#{const_get(s)}m" }.join('')}#{text}#{clear}"
      end

      def colorize_code(code)
        return code unless colorable?

        symbol_state = SymbolState.new
        colored = +''
        length = 0

        Ripper.lex(code).each do |(_line, _col), token, str, expr|
          in_symbol = symbol_state.scan_token(token)
          if seq = dispatch_seq(token, expr, str, in_symbol: in_symbol)
            Reline::Unicode.escape_for_print(str).each_line do |line|
              colored << "#{seq.map { |s| "\e[#{s}m" }.join('')}#{line.sub(/\n?\z/, "#{clear}\\0")}"
            end
          else
            colored << Reline::Unicode.escape_for_print(str)
          end
          length += str.length
        end

        # give up colorizing incomplete Ripper tokens
        return code if length != code.length

        colored
      end

      private

      def dispatch_seq(token, expr, str, in_symbol:)
        if token == :on_comment
          [BLUE, BOLD]
        elsif in_symbol
          [YELLOW]
        elsif TOKEN_KEYWORDS.fetch(token, []).include?(str)
          [CYAN, BOLD]
        elsif (seq, exprs = TOKEN_SEQ_EXPRS[token]; exprs&.any? { |e| (expr & e) != 0 })
          seq
        else
          nil
        end
      end
    end

    # A class to manage a state to know whether the current token is for Symbol or not.
    class SymbolState
      def initialize
        # Push `true` to detect Symbol. `false` to increase the nest level for non-Symbol.
        @stack = []
      end

      # Return true if the token is a part of Symbol.
      def scan_token(token)
        prev_state = @stack.last
        case token
        when :on_symbeg
          @stack << true
        when :on_ident, :on_op, :on_const, :on_ivar, :on_kw
          if @stack.last # Pop only when it's Symbol
            @stack.pop
            return prev_state
          end
        when :on_tstring_beg
          @stack << false
        when :on_embexpr_beg
          @stack << false
          return prev_state
        when :on_tstring_end # :on_tstring_end may close Symbol
          @stack.pop
          return prev_state
        when :on_embexpr_end
          @stack.pop
        end
        @stack.last
      end
    end
    private_constant :SymbolState
  end
end
