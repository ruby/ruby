begin
  require 'iconv'

  module REXML
    module Encoding
      @@__REXML_encoding_methods =<<-EOL
      def decode(str)
        return Iconv::iconv("utf-8", "shift_jis", str)[0]
      end

      def encode content
        return Iconv::iconv("shift_jis", "utf-8", content)[0]
      end
      EOL
    end
  end
rescue LoadError
  begin 
    require 'uconv'

    module REXML
      module Encoding
        @@__REXML_encoding_methods =<<-EOL
        def encode(content)
          Uconv::u8tosjis(content)
        end

        def decode(str)
          Uconv::sjistou8(str)
        end
        EOL
      end
    end
  rescue LoadError
    raise "uconv or iconv is required for Japanese encoding support."
  end
end
