require 'rexml/encoding'

module REXML
	# Generates Source-s.  USE THIS CLASS.
	class SourceFactory
		# Generates a Source object
		# @param arg Either a String, or an IO
		# @return a Source, or nil if a bad argument was given
		def SourceFactory::create_from arg#, slurp=true
			if arg.kind_of? String
				source = Source.new(arg)
			elsif arg.kind_of? IO
				source = IOSource.new(arg)
			end
			source
		end
	end

	# A Source can be searched for patterns, and wraps buffers and other
	# objects and provides consumption of text
	class Source
		include Encoding
		# The current buffer (what we're going to read next)
		attr_reader :buffer
		# The line number of the last consumed text
		attr_reader :line
		attr_reader :encoding

		# Constructor
		# @param arg must be a String, and should be a valid XML document
		def initialize arg
			@orig = @buffer = arg
			self.encoding = check_encoding( @buffer )
			#@buffer = decode(@buffer) unless @encoding == UTF_8
			@line = 0
		end

		# Inherited from Encoding
		# Overridden to support optimized en/decoding
		def encoding=(enc)
			super
			eval <<-EOL
				alias :encode :to_#{encoding.tr('-', '_').downcase}
				alias :decode :from_#{encoding.tr('-', '_').downcase}
			EOL
			@line_break = encode( '>' )
			if enc != UTF_8
				@buffer = decode(@buffer)
				@to_utf = true
			else
				@to_utf = false
			end
		end

		# Scans the source for a given pattern.  Note, that this is not your
		# usual scan() method.  For one thing, the pattern argument has some
		# requirements; for another, the source can be consumed.  You can easily
		# confuse this method.  Originally, the patterns were easier
		# to construct and this method more robust, because this method 
		# generated search regexes on the fly; however, this was 
		# computationally expensive and slowed down the entire REXML package 
		# considerably, since this is by far the most commonly called method.
		# @param pattern must be a Regexp, and must be in the form of
		# /^\s*(#{your pattern, with no groups})(.*)/.  The first group
		# will be returned; the second group is used if the consume flag is
		# set.
		# @param consume if true, the pattern returned will be consumed, leaving
		# everything after it in the Source.
		# @return the pattern, if found, or nil if the Source is empty or the
		# pattern is not found.
		def scan pattern, consume=false
			return nil if @buffer.nil?
			rv = @buffer.scan(pattern)
			@buffer = $' if consume and rv.size>0
			rv
		end

		def read
		end

		def match pattern, consume=false
			md = pattern.match @buffer
			@buffer = $' if consume and md
			return md
		end

		# @return true if the Source is exhausted
		def empty?
			@buffer.nil? or @buffer.strip.nil?
		end

		# @return the current line in the source
		def current_line
			lines = @orig.split
			res = lines.grep @buffer[0..30]
			res = res[-1] if res.kind_of? Array
			lines.index( res ) if res
		end
	end

	# A Source that wraps an IO.  See the Source class for method
	# documentation
	class IOSource < Source
		#attr_reader :block_size

		def initialize arg, block_size=500
			@er_source = @source = arg
			@to_utf = false
			# READLINE OPT
			# The following was commented out when IOSource started using readline
			# to pull the data from the stream.
			#@block_size = block_size
			#super @source.read(@block_size)
			@line_break = '>'
			super @source.readline( @line_break )
		end

		def scan pattern, consume=false
			rv = super
			# You'll notice that this next section is very similar to the same
			# section in match(), but just a liiittle different.  This is
			# because it is a touch faster to do it this way with scan()
			# than the way match() does it; enough faster to warrent duplicating
			# some code
			if rv.size == 0
				until @buffer =~ pattern or @source.nil?
					begin
						# READLINE OPT
						#str = @source.read(@block_size)
						str = @source.readline(@line_break)
						str = decode(str) if @to_utf and str
						@buffer << str
					rescue
						@source = nil
					end
				end
				rv = super
			end
			rv.taint
			rv
		end

		def read
			begin
				str = @source.readline('>')
				str = decode(str) if @to_utf and str 
				@buffer << str
			rescue
				@source = nil
			end
		end

		def match pattern, consume=false
			rv = pattern.match(@buffer)
			@buffer = $' if consume and rv
			while !rv and @source
				begin
					str = @source.readline('>')
					str = decode(str) if @to_utf and str
					@buffer << str
					rv = pattern.match(@buffer)
					@buffer = $' if consume and rv
				rescue
					@source = nil
				end
			end
			rv.taint
			rv
		end
		
		def empty?
			super and ( @source.nil? || @source.eof? )
		end

		# @return the current line in the source
		def current_line
			pos = @er_source.pos				# The byte position in the source
			lineno = @er_source.lineno	# The XML < position in the source
			@er_source.rewind
			line = 0										# The \r\n position in the source
			begin
				while @er_source.pos < pos
					@er_source.readline
					line += 1
				end
			rescue
			end
			[pos, lineno, line]
		end
	end
end
