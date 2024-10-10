module ErrorHighlight
  class DefaultFormatter
    def self.message_for(spot)
      # currently only a one-line code snippet is supported
      if spot[:first_lineno] == spot[:last_lineno]
        spot = truncate(spot)

        indent = spot[:snippet][0...spot[:first_column]].gsub(/[^\t]/, " ")
        marker = indent + "^" * (spot[:last_column] - spot[:first_column])

        "\n\n#{ spot[:snippet] }#{ marker }"
      else
        ""
      end
    end

    def self.viewport_size
      Ractor.current[:__error_highlight_viewport_size__] || terminal_columns
    end

    def self.viewport_size=(viewport_size)
      Ractor.current[:__error_highlight_viewport_size__] = viewport_size
    end

    private
    
    def self.truncate(spot)
      ellipsis = '...'
      snippet = spot[:snippet]
      diff = snippet.size - (viewport_size - ellipsis.size)

      # snippet fits in the terminal
      return spot if diff.negative?

      if spot[:first_column] < diff
        snippet = snippet[0...snippet.size - diff]
        {
          **spot,
          snippet: snippet + ellipsis + "\n",
          last_column: [spot[:last_column], snippet.size].min
        }
      else
        {
          **spot,
          snippet: ellipsis + snippet[diff..-1],
          first_column: spot[:first_column] - (diff - ellipsis.size),
          last_column: spot[:last_column] - (diff - ellipsis.size)
        }
      end
    end
    
    def self.terminal_columns
      # lazy load io/console in case viewport_size is set
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
