# frozen_string_literal: true

module SyntaxSuggest
  # Value object for accessing lex values
  #
  # This lex:
  #
  #   [1, 0], :on_ident, "describe", CMDARG
  #
  # Would translate into:
  #
  #  token.line # => 1
  #  token.type # => :on_indent
  #  token.value # => "describe"
  class Token
    attr_reader :line, :type, :value, :state

    def initialize(line, type, value, state, last_token = nil)
      @line = line
      @type = type
      @value = value
      @state = state

      set_kw_end(last_token)
    end

    private def set_kw_end(last_token)
      @is_end = false
      @is_kw = false
      return if type != :on_kw

      return if last_token && last_token.fname? # https://github.com/ruby/ruby/commit/776759e300e4659bb7468e2b97c8c2d4359a2953

      case value
      when "if", "unless", "while", "until"
        # Only count if/unless when it's not a "trailing" if/unless
        # https://github.com/ruby/ruby/blob/06b44f819eb7b5ede1ff69cecb25682b56a1d60c/lib/irb/ruby-lex.rb#L374-L375
        @is_kw = true unless expr_label?
      when "def", "case", "for", "begin", "class", "module", "do"
        @is_kw = true
      when "end"
        @is_end = true
      end
    end

    def fname?
      state.allbits?(Ripper::EXPR_FNAME)
    end

    def ignore_newline?
      type == :on_ignored_nl
    end

    def is_end?
      @is_end
    end

    def is_kw?
      @is_kw
    end

    def expr_beg?
      state.anybits?(Ripper::EXPR_BEG)
    end

    def expr_label?
      state.allbits?(Ripper::EXPR_LABEL)
    end
  end
end
