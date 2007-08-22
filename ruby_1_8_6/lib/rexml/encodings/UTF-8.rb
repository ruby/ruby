module REXML
  module Encoding
    def encode_utf8 content
      content
    end

    def decode_utf8(str)
      str
    end

    register(UTF_8) do |obj|
      class << obj
        alias decode decode_utf8
        alias encode encode_utf8
      end
    end
  end
end
