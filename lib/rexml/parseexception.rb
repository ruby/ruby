module REXML
	class ParseException < Exception
		attr_accessor :source, :parser, :continued_exception

		def initialize( message, source=nil, parser=nil, exception=nil )
			super(message)
			@source = source
			@parser = parser
			@continued_exception = exception
		end

		def to_s
			# Quote the original exception, if there was one
			if @continued_exception
				err = @continued_exception.message
				err << "\n"
				err << @continued_exception.backtrace[0..3].join("\n")
				err << "\n...\n"
			else
				err = ""
			end

			# Get the stack trace and error message
			err << super

			# Add contextual information
			err << "\n#{@source.current_line}\nLast 80 unconsumed characters:\n#{@source.buffer[0..80].gsub(/\n/, ' ')}\n" if @source
			err << "\nContext:\n#{@parser.context}" if @parser
			err
		end

		def position
			@source.current_line[0] if @source
		end

		def line
			@source.current_line[2] if @source
		end

		def context
			@source.current_line
		end
	end	
end
