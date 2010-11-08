module REXML
  module Encoding
    # ID ---> Encoding object
    attr_reader :encoding
    def encoding=(encoding)
      if encoding.is_a?(String)
        original_encoding = encoding
        encoding = find_encoding(encoding)
        unless encoding
          raise ArgumentError, "Bad encoding name #{original_encoding}"
        end
      end
      return false if defined?(@encoding) and encoding == @encoding
      if encoding and encoding != ::Encoding::UTF_8
        @encoding = encoding
      else
        @encoding = ::Encoding::UTF_8
      end
      true
    end

    def check_encoding(xml)
      # We have to recognize UTF-16, LSB UTF-16, and UTF-8
      if xml[0, 2] == "\xfe\xff"
        xml[0, 2] = ""
        ::Encoding::UTF_16BE
      elsif xml[0, 2] == "\xff\xfe"
        xml[0, 2] = ""
        ::Encoding::UTF_16LE
      else
        if /\A\s*<\?xml\s+version\s*=\s*(['"]).*?\1
            \s+encoding\s*=\s*(["'])(.*?)\2/mx =~ xml
          encoding_name = $3
          if /\Autf-16\z/i =~ encoding_name
            ::Encoding::UTF_16BE
          else
            find_encoding(encoding_name)
          end
        else
          ::Encoding::UTF_8
        end
      end
    end

    def encode(string)
      string.encode(@encoding)
    end

    def decode(string)
      string.encode(::Encoding::UTF_8, @encoding)
    end

    private
    def find_encoding(name)
      case name
      when "UTF-16"
        name = "UTF-16BE"
      when /\Ashift-jis\z/i
        name = "Shift_JIS"
      when /\ACP-(\d+)\z/
        name = "CP#{$1}"
      end
      ::Encoding.find(name)
    end
  end
end
