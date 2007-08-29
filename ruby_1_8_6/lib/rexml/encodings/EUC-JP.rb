module REXML
  module Encoding
    begin
      require 'uconv'

      def decode_eucjp(str)
        Uconv::euctou8(str)
      end

      def encode_eucjp content
        Uconv::u8toeuc(content)
      end
    rescue LoadError
      require 'nkf'

      EUCTOU8 = '-Ewm0'
      U8TOEUC = '-Wem0'

      def decode_eucjp(str)
        NKF.nkf(EUCTOU8, str)
      end

      def encode_eucjp content
        NKF.nkf(U8TOEUC, content)
      end
    end

    register("EUC-JP") do |obj|
      class << obj
        alias decode decode_eucjp
        alias encode encode_eucjp
      end
    end
  end
end
