module REXML
  # Defines a set of methods to manipulate quotes for strings
  module StringQuotes
    # Method contributed by Henrik Martensson
    def strip_quotes(quoted_string)
      quoted_string =~ /^[\'\"].*[\'\"]$/ ?
        quoted_string[1, quoted_string.length-2] :
        quoted_string
    end

    def adjust_prologue_quotes(quoted_string, default_quote_char = '"')
      quote_char = default_quote_char
      if @parent != nil and @parent.context != nil and @parent.context[:xml_prologue_quote] != nil
        case @parent.context[:xml_prologue_quote]
        when :quote then quote_char = '"'
        when :apos  then quote_char = "'"
        end
      end
      quoted_string = quote_char + strip_quotes(quoted_string) + quote_char
      quoted_string
    end

  end
end

