module ErrorHighlight
  class DefaultFormatter
    MIN_SNIPPET_WIDTH = 20

    def self.message_for(spot)
      # currently only a one-line code snippet is supported
      return "" unless spot[:first_lineno] == spot[:last_lineno]

      snippet      = spot[:snippet]
      first_column = spot[:first_column]
      last_column  = spot[:last_column]
      ellipsis     = "..."

      # truncate snippet to fit in the viewport
      if snippet_max_width && snippet.size > snippet_max_width
        available_width = snippet_max_width - ellipsis.size
        center          = first_column - snippet_max_width / 2

        visible_start  = last_column < available_width ? 0 : [center, 0].max
        visible_end    = visible_start + snippet_max_width
        visible_start  = snippet.size - snippet_max_width if visible_end > snippet.size

        prefix = visible_start.positive?    ? ellipsis : ""
        suffix = visible_end < snippet.size ? ellipsis : ""

        snippet = prefix + snippet[(visible_start + prefix.size)...(visible_end - suffix.size)] + suffix
        snippet << "\n" unless snippet.end_with?("\n")

        first_column -= visible_start
        last_column  = [last_column - visible_start, snippet.size - 1].min
      end

      indent = snippet[0...first_column].gsub(/[^\t]/, " ")
      marker = indent + "^" * (last_column - first_column)

      "\n\n#{ snippet }#{ marker }"
    end

    def self.snippet_max_width
      return if Ractor.current[:__error_highlight_max_snippet_width__] == :disabled

      Ractor.current[:__error_highlight_max_snippet_width__] ||= terminal_width
    end

    def self.snippet_max_width=(width)
      return Ractor.current[:__error_highlight_max_snippet_width__] = :disabled if width.nil?

      width = width.to_i

      if width < MIN_SNIPPET_WIDTH
        warn "'snippet_max_width' adjusted to minimum value of #{MIN_SNIPPET_WIDTH}."
        width = MIN_SNIPPET_WIDTH
      end

      Ractor.current[:__error_highlight_max_snippet_width__] = width
    end

    def self.terminal_width
      # lazy load io/console, so it's not loaded when snippet_max_width is set
      require "io/console"
      STDERR.winsize[1] if STDERR.tty?
    rescue LoadError, NoMethodError, SystemCallError
      # do not truncate when window size is not available
    end
  end

  def self.formatter
    Ractor.current[:__error_highlight_formatter__] || DefaultFormatter
  end

  def self.formatter=(formatter)
    Ractor.current[:__error_highlight_formatter__] = formatter
  end
end
