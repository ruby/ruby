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
  begin
	require 'iconv'
	module REXML
		module Encoding
			def from_euc_jp(str)
				return Iconv::iconv("utf-8", "euc-jp", str).join('')
			end

			def to_euc_jp content
				return Iconv::iconv("euc-jp", "utf-8", content).join('')
			end
		end
	end
  rescue LoadError
	raise "uconv or iconv is required for Japanese encoding support."
  end
end
