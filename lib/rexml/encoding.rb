module REXML
	module Encoding
		@@uconv_available = false

		ENCODING_CLAIMS = { }

		def Encoding.claim( encoding_str, match=nil )
			if match
				ENCODING_CLAIMS[ match ] = encoding_str
			else
				ENCODING_CLAIMS[ /^\s*<?xml\s*version=(['"]).*?\1\s*encoding=(["'])#{encoding_str}\2/i ] = encoding_str
			end
		end

		# Native, default format is UTF-8, so it is declared here rather than in
		# an encodings/ definition.
		UTF_8 = 'UTF-8'
		claim( UTF_8 )

		# ID ---> Encoding name
		attr_reader :encoding
		def encoding=( enc )
                	enc = UTF_8 unless enc
                	@encoding = enc.upcase
                	require "rexml/encodings/#@encoding" unless @encoding == UTF_8
		end

		def check_encoding str
			rv = ENCODING_CLAIMS.find{|k,v| str =~ k }
			# Raise an exception if there is a declared encoding and we don't
			# recognize it
			unless rv
				if str =~ /^\s*<?xml\s*version=(['"]).*?\1\s*encoding=(["'])(.*?)\2/
					raise "A matching encoding handler was not found for encoding '#{$3}', or the encoding handler failed to load due to a missing support library (such as uconv)."
				else
					return UTF_8
				end
			end
			return rv[1]
		end

		def to_utf_8(str)
			return str
		end

		def from_utf_8 content
			return content
		end
	end

	module Encodingses
		encodings = []
		$:.each do |incl_dir|
			if Dir[ File.join(incl_dir, 'rexml', 'encodings') ].size > 0
				encodings |= Dir[ File.join(incl_dir, 'rexml', 'encodings', '*_decl.rb') ]
			end
			encodings.collect!{ |f| File.basename(f) }
			encodings.uniq!
		end
		encodings.each { |enc| require "rexml/encodings/#{enc}" }
	end
end
