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

  def self.formatter
    @@formatter
  end

  def self.formatter=(formatter)
    @@formatter = formatter
  end

  self.formatter = DefaultFormatter.new
end
