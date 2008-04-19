#
# Handle Unicode-to-Internal conversion
#

module YAML

	#
	# Escape the string, condensing common escapes
	#
	def YAML.escape( value, skip = "" )
		value.gsub( /\\/, "\\\\\\" ).
              gsub( /"/, "\\\"" ).
              gsub( /([\x00-\x1f])/ ) do
                 skip[$&] || ESCAPES[ $&.unpack("C")[0] ]
             end
	end

	#
	# Unescape the condenses escapes
	#
	def YAML.unescape( value )
		value.gsub( /\\(?:([nevfbart\\])|0?x([0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))/ ) {
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
