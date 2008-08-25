module REXML
  module Encoding
    begin
      require 'uconv'

      def decode_sjis content
        Uconv::sjistou8(content)
      end

      def encode_sjis(str)
        Uconv::u8tosjis(str)
      end
    rescue LoadError
      require 'nkf'

      SJISTOU8 = '-Swm0x'
      U8TOSJIS = '-Wsm0x'

      def decode_sjis(str)
        NKF.nkf(SJISTOU8, str)
      end

      def encode_sjis content
        NKF.nkf(U8TOSJIS, content)
      end
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
