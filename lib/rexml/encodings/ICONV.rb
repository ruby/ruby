require "iconv"
raise LoadError unless defined? Iconv

module REXML
  module Encoding
    @@__REXML_encoding_methods =<<-EOL
    def decode( str )
      return Iconv::iconv("utf-8", @encoding, str)[0]
    end

    def encode( content )
      return Iconv::iconv(@encoding, "utf-8", content)[0]
    end
    EOL
  end
end
