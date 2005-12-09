# -*- mode: ruby; ruby-indent-level: 2; indent-tabs-mode: t; tab-width: 2 -*- vim: sw=2 ts=2
module REXML
	module Encoding
               @encoding_methods = {}
               def self.register(enc, &block)
                       @encoding_methods[enc] = block
               end
               def self.apply(obj, enc)
                       @encoding_methods[enc][obj]
               end
               def self.encoding_method(enc)
                       @encoding_methods[enc]
               end

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
				if enc
					raise ArgumentError, "Bad encoding name #{enc}" unless /\A[\w-]+\z/n =~ enc
					@encoding = enc.upcase.untaint
				else
					@encoding = UTF_8
				end
				err = nil
				[@encoding, "ICONV"].each do |enc|
					begin
						require File.join("rexml", "encodings", "#{enc}.rb")
						return Encoding.apply(self, enc)
					rescue LoadError, Exception => err
						end
					end
				puts err.message
				raise ArgumentError, "No decoder found for encoding #@encoding.  Please install iconv."
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
