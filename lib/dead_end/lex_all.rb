module DeadEnd
  # Ripper.lex is not guaranteed to lex the entire source document
  #
  # lex = LexAll.new(source: source)
  # lex.each do |value|
  #   puts value.line
  # end
  class LexAll
    include Enumerable

    def initialize(source: )
      @lex = Ripper.lex(source)
      lineno = @lex.last&.first&.first + 1
      source_lines = source.lines
      last_lineno = source_lines.count

      until lineno >= last_lineno
        lines = source_lines[lineno..-1]

        @lex.concat(Ripper.lex(lines.join, '-', lineno + 1))
        lineno = @lex.last&.first&.first + 1
      end

      @lex.map! {|(line, _), type, token, state| LexValue.new(line, _, type, token, state) }
    end

    def each
      return @lex.each unless block_given?
      @lex.each do |x|
        yield x
      end
    end

    def last
      @lex.last
    end

    # Value object for accessing lex values
    #
    # This lex:
    #
    #   [1, 0], :on_ident, "describe", CMDARG
    #
    # Would translate into:
    #
    #  lex.line # => 1
    #  lex.type # => :on_indent
    #  lex.token # => "describe"
    class LexValue
      attr_reader :line, :type, :token, :state

      def initialize(line, _, type, token, state)
        @line = line
        @type = type
        @token = token
        @state = state
      end

      def expr_label?
        state.allbits?(Ripper::EXPR_LABEL)
      end
    end
  end
end
