#
# This class was contributed by Mikko Tiihonen mikko DOT tiihonen AT hut DOT fi
#
module REXML
  module Encoding
    @@__REXML_encoding_methods = %q~
    # Convert from UTF-8
    def to_iso_8859_15 content
      array_utf8 = content.unpack('U*')
      array_enc = []
      array_utf8.each do |num|
        case num
          # shortcut first bunch basic characters
        when 0..0xA3: array_enc << num
          # characters removed compared to iso-8859-1
        when 0xA4: array_enc << '&#164;'
        when 0xA6: array_enc << '&#166;'
        when 0xA8: array_enc << '&#168;'
        when 0xB4: array_enc << '&#180;'
        when 0xB8: array_enc << '&#184;'
        when 0xBC: array_enc << '&#188;'
        when 0xBD: array_enc << '&#189;'
        when 0xBE: array_enc << '&#190;'
          # characters added compared to iso-8859-1
        when 0x20AC: array_enc << 0xA4 # 0xe2 0x82 0xac
        when 0x0160: array_enc << 0xA6 # 0xc5 0xa0
        when 0x0161: array_enc << 0xA8 # 0xc5 0xa1
        when 0x017D: array_enc << 0xB4 # 0xc5 0xbd
        when 0x017E: array_enc << 0xB8 # 0xc5 0xbe
        when 0x0152: array_enc << 0xBC # 0xc5 0x92
        when 0x0153: array_enc << 0xBD # 0xc5 0x93
        when 0x0178: array_enc << 0xBE # 0xc5 0xb8
        else
          # all remaining basic characters can be used directly
          if num <= 0xFF
            array_enc << num
          else
            # Numeric entity (&#nnnn;); shard by  Stefan Scholl
            array_enc.concat "&\##{num};".unpack('C*')
          end
        end
      end
      array_enc.pack('C*')
    end
    
    # Convert to UTF-8
    def from_iso_8859_15(str)
      array_latin9 = str.unpack('C*')
      array_enc = []
      array_latin9.each do |num|
        case num
          # characters that differ compared to iso-8859-1
        when 0xA4: array_enc << 0x20AC
        when 0xA6: array_enc << 0x0160
        when 0xA8: array_enc << 0x0161
        when 0xB4: array_enc << 0x017D
        when 0xB8: array_enc << 0x017E
        when 0xBC: array_enc << 0x0152
        when 0xBD: array_enc << 0x0153
        when 0xBE: array_enc << 0x0178
        else
          array_enc << num
        end
      end
      array_enc.pack('U*')
    end
    ~
  end
end
