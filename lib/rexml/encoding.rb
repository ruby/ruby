module REXML
	module Encoding
		@@uconv_available = false

		# Native, default format is UTF-8, so it is declared here rather than in
		# an encodings/ definition.
		UTF_8 = 'UTF-8'
		UTF_16 = 'UTF-16'
		UNILE = 'UNILE'

		# ID ---> Encoding name
		attr_reader :encoding
		def encoding=( enc )
			old_verbosity = $VERBOSE
			begin
				$VERBOSE = false
				return if defined? @encoding and enc == @encoding
				if enc and enc != UTF_8
					@encoding = enc.upcase
					begin
            load 'rexml/encodings/ICONV.rb'
						instance_eval @@__REXML_encoding_methods
						Iconv::iconv( UTF_8, @encoding, "" )
					rescue LoadError, Exception => err
						raise "Bad encoding name #@encoding" unless @encoding =~ /^[\w-]+$/
						@encoding.untaint 
						enc_file = File.join( "rexml", "encodings", "#@encoding.rb" )
						begin
              load enc_file
							instance_eval @@__REXML_encoding_methods
						rescue LoadError
              puts $!.message
							raise Exception.new( "No decoder found for encoding #@encoding.  Please install iconv." )
						end
					end
				else
					enc = UTF_8
					@encoding = enc.upcase
          load 'rexml/encodings/UTF-8.rb' 
					instance_eval @@__REXML_encoding_methods
				end
			ensure
				$VERBOSE = old_verbosity
			end
		end

		def check_encoding str
			# We have to recognize UTF-16, LSB UTF-16, and UTF-8
			return UTF_16 if str[0] == 254 && str[1] == 255
			return UNILE if str[0] == 255 && str[1] == 254
			str =~ /^\s*<?xml\s*version=(['"]).*?\2\s*encoding=(["'])(.*?)\2/um
			return $1.upcase if $1
			return UTF_8
		end
	end
end
