require "iconv"
raise LoadError unless defined? Iconv

module REXML
	module Encoding
		def decode( str )
			return Iconv::iconv(UTF_8, @encoding, str)[0]
		end

		def encode( content )
			return Iconv::iconv(@encoding, UTF_8, content)[0]
		end
	end
end
