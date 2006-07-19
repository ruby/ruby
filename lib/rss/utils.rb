module RSS
  module Utils
    module_function

    # Convert a name_with_underscores to CamelCase.
    def to_class_name(name)
      name.split(/_/).collect do |part|
        "#{part[0, 1].upcase}#{part[1..-1]}"
      end.join("")
    end
    
    def get_file_and_line_from_caller(i=0)
      file, line, = caller[i].split(':')
      [file, line.to_i]
    end

    # escape '&', '"', '<' and '>' for use in HTML.
    def html_escape(s)
      s.to_s.gsub(/&/, "&amp;").gsub(/\"/, "&quot;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
    end
    alias h html_escape
    
    # If +value+ is an instance of class +klass+, return it, else
    # create a new instance of +klass+ with value +value+.
    def new_with_value_if_need(klass, value)
      if value.is_a?(klass)
        value
      else
        klass.new(value)
      end
    end

    def element_initialize_arguments?(args)
      [true, false].include?(args[0]) and args[1].is_a?(Hash)
    end
  end
end
