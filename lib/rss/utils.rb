module RSS

  module Utils

    module_function
    def to_class_name(name)
      name.split(/_/).collect do |part|
        "#{part[0, 1].upcase}#{part[1..-1]}"
      end.join("")
    end
    
    def get_file_and_line_from_caller(i=0)
      file, line, = caller[i].split(':')
      [file, line.to_i]
    end

    def html_escape(s)
      s.to_s.gsub(/&/, "&amp;").gsub(/\"/, "&quot;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
    end
    alias h html_escape
    
    def new_with_value_if_need(klass, value)
      if value.is_a?(klass)
        value
      else
        klass.new(value)
      end
    end
  end

end
