begin
	require 'uconv'

	module REXML
		module Encoding
			def from_shift_jis(str)
				Uconv::u8tosjis(content)
			end

			def to_shift_jis content
				Uconv::sjistou8(str)
			end
		end
	end
rescue LoadError
  begin
	require 'iconv'
	module REXML
		module Encoding
			def from_shift_jis(str)
				return Iconv::iconv("utf-8", "shift-jis", str)[0]
			end

			def to_shift_jis content
				return Iconv::iconv("euc-jp", "shift-jis", content)[0]
			end
		end
	end
  rescue LoadError
	raise "uconv or iconv is required for Japanese encoding support."
  end
end
