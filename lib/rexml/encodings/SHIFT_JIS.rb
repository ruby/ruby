begin
	require 'uconv'

	module REXML
		module Encoding
			def to_shift_jis content
				Uconv::u8tosjis(content)
			end

			def from_shift_jis(str)
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
				return Iconv::iconv("utf-8", "shift_jis", str).join('')
			end

			def to_shift_jis content
				return Iconv::iconv("shift_jis", "utf-8", content).join('')
			end
		end
	end
  rescue LoadError
	raise "uconv or iconv is required for Japanese encoding support."
  end

end
