module SM

  # We manage a set of attributes. Each attribute has a symbol name
  # and a bit value

  class Attribute
    SPECIAL = 1

    @@name_to_bitmap = { :_SPECIAL_ => SPECIAL }
    @@next_bitmap = 2

    def Attribute.bitmap_for(name)
      bitmap = @@name_to_bitmap[name]
      if !bitmap
        bitmap = @@next_bitmap
        @@next_bitmap <<= 1
        @@name_to_bitmap[name] = bitmap
      end
      bitmap
    end

    def Attribute.as_string(bitmap)
      return "none" if bitmap.zero?
      res = []
      @@name_to_bitmap.each do |name, bit|
        res << name if (bitmap & bit) != 0
      end
      res.join(",")
    end

    def Attribute.each_name_of(bitmap)
      @@name_to_bitmap.each do |name, bit|
        next if bit == SPECIAL
        yield name.to_s if (bitmap & bit) != 0
      end
    end
  end


  # An AttrChanger records a change in attributes. It contains
  # a bitmap of the attributes to turn on, and a bitmap of those to
  # turn off

  AttrChanger = Struct.new(:turn_on, :turn_off)
  class AttrChanger
    def to_s
      "Attr: +#{Attribute.as_string(@turn_on)}/-#{Attribute.as_string(@turn_on)}"
    end
  end

  # An array of attributes which parallels the characters in a string
  class AttrSpan
    def initialize(length)
      @attrs = Array.new(length, 0)
    end

    def set_attrs(start, length, bits)
      for i in start ... (start+length)
        @attrs[i] |= bits
      end
    end

    def [](n)
      @attrs[n]
    end
  end

  ##
  # Hold details of a special sequence

  class Special
    attr_reader   :type
    attr_accessor :text

    def initialize(type, text)
      @type, @text = type, text
    end

    def ==(o)
      self.text == o.text && self.type == o.type
    end

    def to_s
      "Special: type=#{type}, text=#{text.dump}"
    end
  end
  
  class AttributeManager

    NULL = "\000".freeze

    ##
    # We work by substituting non-printing characters in to the
    # text. For now I'm assuming that I can substitute
    # a character in the range 0..8 for a 7 bit character
    # without damaging the encoded string, but this might
    # be optimistic
    #

=begin
    ATTR_FLAG  = 001
    A_START    = 002
    A_END      = 003
    A_SPECIAL_START = 005
    A_SPECIAL_END   = 006

    START_ATTR   = ATTR_FLAG.chr + A_START.chr
    END_ATTR     = ATTR_FLAG.chr + A_END.chr

    START_SPECIAL = ATTR_FLAG.chr + A_SPECIAL_START.chr
    END_SPECIAL   = ATTR_FLAG.chr + A_SPECIAL_END.chr

=end
    A_PROTECT  = 004
    PROTECT_ATTR  = A_PROTECT.chr

    # This maps delimiters that occur around words (such as
    # *bold* or +tt+) where the start and end delimiters
    # and the same. This lets us optimize the regexp
    MATCHING_WORD_PAIRS = {}

    # And this is used when the delimiters aren't the same. In this
    # case the hash maps a pattern to the attribute character
    WORD_PAIR_MAP = {}

    # This maps HTML tags to the corresponding attribute char
    HTML_TAGS = {}

    # And this maps _special_ sequences to a name. A special sequence
    # is something like a WikiWord
    SPECIAL = {}

    # Return an attribute object with the given turn_on
    # and turn_off bits set

    def attribute(turn_on, turn_off)
      AttrChanger.new(turn_on, turn_off)
    end


    def change_attribute(current, new)
      diff = current ^ new
      attribute(new & diff, current & diff)
    end

    def changed_attribute_by_name(current_set, new_set)
      current = new = 0
      current_set.each {|name| current |= Attribute.bitmap_for(name) }
      new_set.each {|name| new |= Attribute.bitmap_for(name) }
      change_attribute(current, new)
    end

    def copy_string(start_pos, end_pos)
      res = @str[start_pos...end_pos]
      res.gsub!(/\000/, '')
      res
    end

    # Map attributes like <b>text</b>to the sequence \001\002<char>\001\003<char>,
    # where <char> is a per-attribute specific character

    def convert_attrs(str, attrs)
      # first do matching ones
      tags = MATCHING_WORD_PAIRS.keys.join("")
      re = "(^|\\W)([#{tags}])([A-Za-z_]+?)\\2(\\W|\$)"
#      re = "(^|\\W)([#{tags}])(\\S+?)\\2(\\W|\$)"
      1 while str.gsub!(Regexp.new(re)) {
        attr = MATCHING_WORD_PAIRS[$2];
        attrs.set_attrs($`.length + $1.length + $2.length, $3.length, attr)
        $1 + NULL*$2.length + $3 + NULL*$2.length + $4
      }

      # then non-matching
      unless WORD_PAIR_MAP.empty?
        WORD_PAIR_MAP.each do |regexp, attr|
          str.gsub!(regexp) { 
            attrs.set_attrs($`.length + $1.length, $2.length, attr)
            NULL*$1.length + $2 + NULL*$3.length
          }
        end
      end
    end

    def convert_html(str, attrs)
      tags = HTML_TAGS.keys.join("|")
      re = "<(#{tags})>(.*?)</\\1>"
      1 while str.gsub!(Regexp.new(re, Regexp::IGNORECASE)) {
        attr = HTML_TAGS[$1.downcase]
        html_length = $1.length + 2
        seq = NULL * html_length
        attrs.set_attrs($`.length + html_length, $2.length, attr)
        seq + $2 + seq + NULL
      }
    end

    def convert_specials(str, attrs)
      unless SPECIAL.empty?
        SPECIAL.each do |regexp, attr|
          str.scan(regexp) do
            attrs.set_attrs($`.length, $1.length, attr | Attribute::SPECIAL)
          end
        end
      end
    end

    # A \ in front of a character that would normally be
    # processed turns off processing. We do this by turning
    # \< into <#{PROTECT}
    
    PROTECTABLE = [ "<" << "\\" ]  #"


    def mask_protected_sequences
      protect_pattern = Regexp.new("\\\\([#{Regexp.escape(PROTECTABLE.join(''))}])")
      @str.gsub!(protect_pattern, "\\1#{PROTECT_ATTR}")
    end

    def unmask_protected_sequences
      @str.gsub!(/(.)#{PROTECT_ATTR}/, '\1')
    end

    def initialize
      add_word_pair("*", "*", :BOLD)
      add_word_pair("_", "_", :EM)
      add_word_pair("+", "+", :TT)
      
      add_html("em", :EM)
      add_html("i",  :EM)
      add_html("b",  :BOLD)
      add_html("tt", :TT)
    end

    def add_word_pair(start, stop, name)
      raise "Word flags may not start '<'" if start[0] == ?<
      bitmap = Attribute.bitmap_for(name)
      if start == stop
        MATCHING_WORD_PAIRS[start] = bitmap
      else
        pattern = Regexp.new("(" + Regexp.escape(start) + ")" +
#                             "([A-Za-z]+)" +
                             "(\\S+)" +
                             "(" + Regexp.escape(stop) +")")
        WORD_PAIR_MAP[pattern] = bitmap
      end
      PROTECTABLE << start[0,1]
      PROTECTABLE.uniq!
    end

    def add_html(tag, name)
      HTML_TAGS[tag.downcase] = Attribute.bitmap_for(name)
    end

    def add_special(pattern, name)
      SPECIAL[pattern] = Attribute.bitmap_for(name)
    end

    def flow(str)
      @str = str
      @attrs = AttrSpan.new(str.length)

      puts("Before flow, str='#{@str.dump}'") if $DEBUG
      mask_protected_sequences
      convert_attrs(@str, @attrs)
      convert_html(@str, @attrs)
      convert_specials(str, @attrs)
      unmask_protected_sequences
      puts("After flow, str='#{@str.dump}'") if $DEBUG
      return split_into_flow
    end

    def display_attributes
      puts
      puts @str.tr(NULL, "!")
      bit = 1
      16.times do |bno|
        line = ""
        @str.length.times do |i|
          if (@attrs[i] & bit) == 0
            line << " "
          else
            if bno.zero?
              line << "S"
            else
              line << ("%d" % (bno+1))
            end
          end
        end
        puts(line) unless line =~ /^ *$/
        bit <<= 1
      end
    end

    def split_into_flow

      display_attributes if $DEBUG

      res = []
      current_attr = 0
      str = ""

      
      str_len = @str.length

      # skip leading invisible text
      i = 0
      i += 1 while i < str_len and @str[i].zero?
      start_pos = i

      # then scan the string, chunking it on attribute changes
      while i < str_len
        new_attr = @attrs[i]
        if new_attr != current_attr
          if i > start_pos
            res << copy_string(start_pos, i)
            start_pos = i
          end

          res << change_attribute(current_attr, new_attr)
          current_attr = new_attr

          if (current_attr & Attribute::SPECIAL) != 0
            i += 1 while i < str_len and (@attrs[i] & Attribute::SPECIAL) != 0
            res << Special.new(current_attr, copy_string(start_pos, i))
            start_pos = i
            next
          end
        end

        # move on, skipping any invisible characters
        begin
          i += 1
        end while i < str_len and @str[i].zero?
      end
      
      # tidy up trailing text
      if start_pos < str_len
        res << copy_string(start_pos, str_len)
      end

      # and reset to all attributes off
      res << change_attribute(current_attr, 0) if current_attr != 0

      return res
    end

  end

end
