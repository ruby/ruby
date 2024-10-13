module ErrorHighlight
  class DefaultFormatter
    def self.message_for(spot)
      # currently only a one-line code snippet is supported
      return "" unless spot[:first_lineno] == spot[:last_lineno]

      snippet      = spot[:snippet]
      first_column = spot[:first_column]
      last_column  = spot[:last_column]

      # truncate snippet to fit in the viewport
      if snippet.size > viewport_size
        visible_start = [first_column - viewport_size / 2, 0].max
        visible_end   = visible_start + viewport_size

        # avoid centering the snippet when the error is at the end of the line
        visible_start = snippet.size - viewport_size if visible_end > snippet.size

        prefix = visible_start.positive?    ? "..." : ""
        suffix = visible_end < snippet.size ? "..." : ""

        snippet = prefix + snippet[(visible_start + prefix.size)...(visible_end - suffix.size)] + suffix
        snippet << "\n" unless snippet.end_with?("\n")

        first_column = first_column - visible_start
        last_column  = [last_column - visible_start, snippet.size - 1].min
      end

      indent = snippet[0...first_column].gsub(/[^\t]/, " ")
      marker = indent + "^" * (last_column - first_column)

      "\n\n#{ snippet }#{ marker }"
    end

    def self.viewport_size
      Ractor.current[:__error_highlight_viewport_size__] ||= terminal_columns
    end

    def self.viewport_size=(viewport_size)
      Ractor.current[:__error_highlight_viewport_size__] = viewport_size
    end

    def self.terminal_columns
      # lazy load io/console, so it's not loaded when viewport_size is set
      require "io/console"
      IO.console.winsize[1]
    end
  end

  def self.formatter
    Ractor.current[:__error_highlight_formatter__] || DefaultFormatter
  end

  def self.formatter=(formatter)
    Ractor.current[:__error_highlight_formatter__] = formatter
  end
end
