module RSS

  module Utils

    def get_file_and_line_from_caller(i=0)
      file, line, = caller[i].split(':')
      [file, line.to_i]
    end

    def html_escape(s)
      s.to_s.gsub(/&/, "&amp;").gsub(/\"/, "&quot;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
    end
    alias h html_escape
    
  end

end
