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
    BLUE      = 34
    MAGENTA   = 35
    CYAN      = 36

    TOKEN_KEYWORDS = {
      on_kw: ['nil', 'self', 'true', 'false'],
      on_const: ['ENV'],
    }

    begin
      TOKEN_SEQ_EXPRS = {
        on_CHAR:            [[BLUE, BOLD],            [Ripper::EXPR_END]],
        on_const:           [[BLUE, BOLD, UNDERLINE], [Ripper::EXPR_ARG, Ripper::EXPR_CMDARG, Ripper::EXPR_ENDFN]],
        on_embexpr_beg:     [[RED],                   [Ripper::EXPR_BEG, Ripper::EXPR_END]],
        on_embexpr_end:     [[RED],                   [Ripper::EXPR_END, Ripper::EXPR_ENDFN, Ripper::EXPR_CMDARG]],
        on_embvar:          [[RED],                   [Ripper::EXPR_BEG]],
        on_heredoc_beg:     [[RED],                   [Ripper::EXPR_BEG]],
        on_heredoc_end:     [[RED],                   [Ripper::EXPR_BEG]],
        on_ident:           [[BLUE, BOLD],            [Ripper::EXPR_ENDFN]],
        on_int:             [[BLUE, BOLD],            [Ripper::EXPR_END]],
        on_float:           [[MAGENTA, BOLD],         [Ripper::EXPR_END]],
        on_kw:              [[GREEN],                 [Ripper::EXPR_ARG, Ripper::EXPR_CLASS, Ripper::EXPR_BEG, Ripper::EXPR_END, Ripper::EXPR_FNAME]],
        on_label:           [[MAGENTA],               [Ripper::EXPR_LABELED]],
        on_label_end:       [[RED],                   [Ripper::EXPR_BEG]],
        on_qwords_beg:      [[RED],                   [Ripper::EXPR_BEG]],
        on_qsymbols_beg:    [[RED],                   [Ripper::EXPR_BEG]],
        on_regexp_beg:      [[RED, BOLD],             [Ripper::EXPR_BEG]],
        on_regexp_end:      [[RED, BOLD],             [Ripper::EXPR_BEG]],
        on_symbeg:          [[BLUE, BOLD],            [Ripper::EXPR_FNAME]],
        on_tstring_beg:     [[RED],                   [Ripper::EXPR_BEG, Ripper::EXPR_END, Ripper::EXPR_ARG, Ripper::EXPR_CMDARG]],
        on_tstring_content: [[RED],                   [Ripper::EXPR_BEG, Ripper::EXPR_END, Ripper::EXPR_ARG, Ripper::EXPR_CMDARG, Ripper::EXPR_FNAME]],
        on_tstring_end:     [[RED],                   [Ripper::EXPR_END]],
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

        colored = +''
        length = 0
        Ripper.lex(code).each do |(_line, _col), token, str, expr|
          if seq = dispatch_seq(token, expr, str)
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

      def dispatch_seq(token, expr, str)
        if token == :on_comment
          [BLUE, BOLD]
        elsif TOKEN_KEYWORDS.fetch(token, []).include?(str)
          [CYAN, BOLD]
        elsif (seq, exprs = TOKEN_SEQ_EXPRS[token]; exprs&.any? { |e| (expr & e) != 0 })
          seq
        else
          nil
        end
      end
    end
  end
end
