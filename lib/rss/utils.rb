module RSS

	module Utils

		def get_file_and_line_from_caller(i=0)
			tmp = caller[i].split(':')
			line = tmp.pop.to_i
			file = tmp.join(':')
			[file, line]
		end

		def html_escape(s)
			s.to_s.gsub(/&/, "&amp;").gsub(/\"/, "&quot;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
		end
		alias h html_escape
		
	end

end
