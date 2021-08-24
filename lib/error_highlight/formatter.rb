# frozen_string_literal: true

module ErrorHighlight
  class DefaultFormatter
    def message_for(spot)
      # currently only a one-line code snippet is supported
      if spot[:first_lineno] == spot[:last_lineno]
        indent = spot[:snippet][0...spot[:first_column]].gsub(/[^\t]/, " ")
        marker = indent + "^" * (spot[:last_column] - spot[:first_column])

        "\n\n#{ spot[:snippet] }#{ marker }"
      else
        ""
      end
    end
  end

  DEFAULT_FORMATTER = DefaultFormatter.new
  Ractor.make_shareable(DEFAULT_FORMATTER) if defined?(Ractor)

  def self.formatter
    DEFAULT_FORMATTER
  end

  def self.formatter=(formatter)
    provider = proc {
      formatter
    }
    Ractor.make_shareable(provider) if defined?(Ractor)
    define_singleton_method(:formatter, &provider)
  end
end
