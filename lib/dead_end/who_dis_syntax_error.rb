# frozen_string_literal: true

module DeadEnd
  # Determines what type of syntax error is in the source
  #
  # Example:
  #
  #   puts WhoDisSyntaxError.new("def foo;").call.error_symbol
  #   # => :missing_end
  class WhoDisSyntaxError < Ripper
    class Null
      def error_symbol; :missing_end; end
      def unmatched_symbol; :end ; end
    end
    attr_reader :error, :run_once

    # Return options:
    #   - :missing_end
    #   - :unmatched_syntax
    #   - :unknown
    def error_symbol
      call
      @error_symbol
    end

    # Return options:
    #   - :end
    #   - :|
    #   - :}
    #   - :unknown
    def unmatched_symbol
      call
      @unmatched_symbol
    end

    def call
      @run_once ||= begin
        parse
        true
      end
      self
    end

    def on_parse_error(msg)
      return if @error_symbol && @unmatched_symbol

      @error = msg
      @unmatched_symbol = :unknown

      case @error
      when /unexpected end-of-input/
        @error_symbol = :missing_end
      when /expecting end-of-input/
        @unmatched_symbol = :end
        @error_symbol = :unmatched_syntax
      when /unexpected .* expecting '(?<unmatched_symbol>.*)'/
        @unmatched_symbol = $1.to_sym if $1
        @error_symbol = :unmatched_syntax
      when /unexpected `end'/,          # Ruby 2.7 and 3.0
           /unexpected end/,            # Ruby 2.6
           /unexpected keyword_end/i    # Ruby 2.5

        @error_symbol = :unmatched_syntax
      else
        @error_symbol = :unknown
      end
    end
  end
end
