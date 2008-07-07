module REXML
  module Encoding
    # Convert from UTF-8
    def encode_ascii content
      array_utf8 = content.unpack('U*')
      array_enc = []
      array_utf8.each do |num|
        if num <= 0x7F
          array_enc << num
        else
          # Numeric entity (&#nnnn;); shard by  Stefan Scholl
          array_enc.concat "&\##{num};".unpack('C*')
        end
      end
      array_enc.pack('C*')
    end

    # Convert to UTF-8
    def decode_ascii(str)
      str.unpack('C*').pack('U*')
    end

    register("US-ASCII") do |obj|
      class << obj
        alias decode decode_ascii
        alias encode encode_ascii
      end
    end
  end
end
