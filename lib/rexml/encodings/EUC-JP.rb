begin
	require 'uconv'

	module REXML
		module Encoding
			def from_euc_jp(str)
				return Uconv::euctou8(str)
			end

			def to_euc_jp content
				return Uconv::u8toeuc(content)
			end
		end
	end
rescue LoadError
	raise "uconv is required for Japanese encoding support."
end
