require 'uconv'

module REXML
  module Encoding
    def decode_sjis content
      Uconv::u8tosjis(content)
    end

    def encode_sjis(str)
      Uconv::sjistou8(str)
    end

    b = proc do |obj|
      class << obj
        alias decode decode_sjis
        alias encode encode_sjis
      end
    end
    register("SHIFT-JIS", &b)
    register("SHIFT_JIS", &b)
  end
end
