require 'uconv'

module REXML
  module Encoding
    def decode_eucjp(str)
      Uconv::euctou8(str)
    end

    def encode_eucjp content
      Uconv::u8toeuc(content)
    end

    register("EUC-JP") do |obj|
      class << obj
        alias decode decode_eucjp
        alias encode encode_eucjp
      end
    end
  end
end
