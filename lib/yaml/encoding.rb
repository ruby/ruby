#
# Handle Unicode-to-Internal conversion
#

module YAML

	#
	# Encodings ( $-K to ICONV )
	#
	CHARSETS = {
		'NONE' => 'LATIN1',
		'ASCII' => 'US-ASCII',
		'UTF-8' => 'UTF-8',
		'EUC' => 'EUC-JP',
		'SJIS' => 'SHIFT-JIS'
	}

	#
	# YAML documents can be in UTF-8, UTF-16 or UTF-32
	# So let's read and write in Unicode
	#

    @@unicode = false
	begin
		require 'iconv'
		DEFAULTS[:Encoding] = :Utf8
	rescue LoadError
	end

    def YAML.unicode; @@unicode; end
    def YAML.unicode=( bool ); @@unicode = bool; end

	#
	# Unicode conversion
	#
    
	def YAML.utf_to_internal( str, from_enc )
		return unless str
		to_enc = CHARSETS[$-K]
		case from_enc
			when :Utf32
				Iconv.iconv( to_enc, 'UTF-32', str )[0]
			when :Utf16
				Iconv.iconv( to_enc, 'UTF-16', str )[0]
			when :Utf8
				Iconv.iconv( to_enc, 'UTF-8', str )[0]
			when :None
				str
			else
				raise YAML::Error, ERROR_UNSUPPORTED_ENCODING % from_enc.inspect
		end
	end

	def YAML.internal_to_utf( str, to_enc )
		return unless str
		from_enc = CHARSETS[$-K]
		case to_enc
			when :Utf32
				Iconv.iconv( 'UTF-32', from_enc, str )[0]
			when :Utf16                        
				Iconv.iconv( 'UTF-16', from_enc, str )[0]
			when :Utf8                         
				Iconv.iconv( 'UTF-8', from_enc, str )[0]
			when :None
				str
			else
				raise YAML::Error, ERROR_UNSUPPORTED_ENCODING % to_enc.inspect
		end
	end

	def YAML.sniff_encoding( str )
		unless YAML::unicode
			:None
		else
			case str
				when /^\x00\x00\xFE\xFF/	# UTF-32
					:Utf32
				when /^\xFE\xFF/	# UTF-32BE
					:Utf16
				else
					:Utf8
			end
		end
	end

	def YAML.enc_separator( enc )
		case enc
			when :Utf32
				"\000\000\000\n"
			when :Utf16
				"\000\n"
			when :Utf8
				"\n"
			when :None
				"\n"
			else
				raise YAML::Error, ERROR_UNSUPPORTED_ENCODING % enc.inspect
		end
	end

	#
	# Escape the string, condensing common escapes
	#
	def YAML.escape( value )
		value.gsub( /\\/, "\\\\\\" ).gsub( /"/, "\\\"" ).gsub( /([\x00-\x1f])/ ) { |x| ESCAPES[ x.unpack("C")[0] ] }
	end

	#
	# Unescape the condenses escapes
	#
	def YAML.unescape( value )
		value.gsub( /\\(?:([nevbr\\fartz])|0?x([0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))/ ) { |x| 
			if $3
				["#$3".hex ].pack('U*')
			elsif $2
				[$2].pack( "H2" ) 
			else
				UNESCAPES[$1] 
			end
		}
	end

end
