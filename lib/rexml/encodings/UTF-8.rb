module REXML
  module Encoding
    @@__REXML_encoding_methods =<<-EOL
    def encode content
      content
    end

    def decode(str)
      str
    end
    EOL
  end
end
