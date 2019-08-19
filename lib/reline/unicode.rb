class Reline::Unicode
  EscapedPairs = {
    0x00 => '^@',
    0x01 => '^A', # C-a
    0x02 => '^B',
    0x03 => '^C',
    0x04 => '^D',
    0x05 => '^E',
    0x06 => '^F',
    0x07 => '^G',
    0x08 => '^H', # Backspace
    0x09 => '^I',
    0x0A => '^J',
    0x0B => '^K',
    0x0C => '^L',
    0x0D => '^M', # Enter
    0x0E => '^N',
    0x0F => '^O',
    0x10 => '^P',
    0x11 => '^Q',
    0x12 => '^R',
    0x13 => '^S',
    0x14 => '^T',
    0x15 => '^U',
    0x16 => '^V',
    0x17 => '^W',
    0x18 => '^X',
    0x19 => '^Y',
    0x1A => '^Z', # C-z
    0x1B => '^[', # C-[ C-3
    0x1D => '^]', # C-]
    0x1E => '^^', # C-~ C-6
    0x1F => '^_', # C-_ C-7
    0x7F => '^?', # C-? C-8
  }
  EscapedChars = EscapedPairs.keys.map(&:chr)

  def self.get_mbchar_byte_size_by_first_char(c)
    # Checks UTF-8 character byte size
    case c.ord
    # 0b0xxxxxxx
    when ->(code) { (code ^ 0b10000000).allbits?(0b10000000) } then 1
    # 0b110xxxxx
    when ->(code) { (code ^ 0b00100000).allbits?(0b11100000) } then 2
    # 0b1110xxxx
    when ->(code) { (code ^ 0b00010000).allbits?(0b11110000) } then 3
    # 0b11110xxx
    when ->(code) { (code ^ 0b00001000).allbits?(0b11111000) } then 4
    # 0b111110xx
    when ->(code) { (code ^ 0b00000100).allbits?(0b11111100) } then 5
    # 0b1111110x
    when ->(code) { (code ^ 0b00000010).allbits?(0b11111110) } then 6
    # successor of mbchar
    else 0
    end
  end

  def self.escape_for_print(str)
    str.chars.map! { |gr|
      escaped = EscapedPairs[gr.ord]
      if escaped && gr != -"\n" && gr != -"\t"
        escaped
      else
        gr
      end
    }.join
  end

  def self.get_mbchar_width(mbchar)
    case mbchar.encode(Encoding::UTF_8)
    when *EscapedChars # ^ + char, such as ^M, ^H, ^[, ...
      2
    when /^\u{2E3B}/ # THREE-EM DASH
      3
    when /^\p{M}/
      0
    when EastAsianWidth::TYPE_A
      Reline.ambiguous_width
    when EastAsianWidth::TYPE_F, EastAsianWidth::TYPE_W
      2
    when EastAsianWidth::TYPE_H, EastAsianWidth::TYPE_NA, EastAsianWidth::TYPE_N
      1
    else
      nil
    end
  end

  def self.get_next_mbchar_size(line, byte_pointer)
    grapheme = line.byteslice(byte_pointer..-1).grapheme_clusters.first
    grapheme ? grapheme.bytesize : 0
  end

  def self.get_prev_mbchar_size(line, byte_pointer)
    if byte_pointer.zero?
      0
    else
      grapheme = line.byteslice(0..(byte_pointer - 1)).grapheme_clusters.last
      grapheme ? grapheme.bytesize : 0
    end
  end

  def self.em_forward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.em_forward_word_with_capitalization(line, byte_pointer)
    width = 0
    byte_size = 0
    new_str = String.new
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
      new_str += mbchar
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    first = true
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
      if first
        new_str += mbchar.upcase
        first = false
      else
        new_str += mbchar.downcase
      end
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width, new_str]
  end

  def self.em_backward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.em_big_backward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar =~ /\S/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar =~ /\s/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.ed_transpose_words(line, byte_pointer)
    right_word_start = nil
    size = get_next_mbchar_size(line, byte_pointer)
    mbchar = line.byteslice(byte_pointer, size)
    if size.zero?
      # ' aaa bbb [cursor]'
      byte_size = 0
      while 0 < (byte_pointer + byte_size)
        size = get_prev_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size - size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
        byte_size -= size
      end
      while 0 < (byte_pointer + byte_size)
        size = get_prev_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size - size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
        byte_size -= size
      end
      right_word_start = byte_pointer + byte_size
      byte_size = 0
      while line.bytesize > (byte_pointer + byte_size)
        size = get_next_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
        byte_size += size
      end
      after_start = byte_pointer + byte_size
    elsif mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
      # ' aaa bb[cursor]b'
      byte_size = 0
      while 0 < (byte_pointer + byte_size)
        size = get_prev_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size - size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
        byte_size -= size
      end
      right_word_start = byte_pointer + byte_size
      byte_size = 0
      while line.bytesize > (byte_pointer + byte_size)
        size = get_next_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
        byte_size += size
      end
      after_start = byte_pointer + byte_size
    else
      byte_size = 0
      while (line.bytesize - 1) > (byte_pointer + byte_size)
        size = get_next_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size, size)
        break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
        byte_size += size
      end
      if (byte_pointer + byte_size) == (line.bytesize - 1)
        # ' aaa bbb [cursor] '
        after_start = line.bytesize
        while 0 < (byte_pointer + byte_size)
          size = get_prev_mbchar_size(line, byte_pointer + byte_size)
          mbchar = line.byteslice(byte_pointer + byte_size - size, size)
          break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
          byte_size -= size
        end
        while 0 < (byte_pointer + byte_size)
          size = get_prev_mbchar_size(line, byte_pointer + byte_size)
          mbchar = line.byteslice(byte_pointer + byte_size - size, size)
          break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
          byte_size -= size
        end
        right_word_start = byte_pointer + byte_size
      else
        # ' aaa [cursor] bbb '
        right_word_start = byte_pointer + byte_size
        while line.bytesize > (byte_pointer + byte_size)
          size = get_next_mbchar_size(line, byte_pointer + byte_size)
          mbchar = line.byteslice(byte_pointer + byte_size, size)
          break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
          byte_size += size
        end
        after_start = byte_pointer + byte_size
      end
    end
    byte_size = right_word_start - byte_pointer
    while 0 < (byte_pointer + byte_size)
      size = get_prev_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size - size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\p{Word}/
      byte_size -= size
    end
    middle_start = byte_pointer + byte_size
    byte_size = middle_start - byte_pointer
    while 0 < (byte_pointer + byte_size)
      size = get_prev_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size - size, size)
      break if mbchar.encode(Encoding::UTF_8) =~ /\P{Word}/
      byte_size -= size
    end
    left_word_start = byte_pointer + byte_size
    [left_word_start, middle_start, right_word_start, after_start]
  end

  def self.vi_big_forward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while (line.bytesize - 1) > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar =~ /\s/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while (line.bytesize - 1) > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar =~ /\S/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.vi_big_forward_end_word(line, byte_pointer)
    if (line.bytesize - 1) > byte_pointer
      size = get_next_mbchar_size(line, byte_pointer)
      mbchar = line.byteslice(byte_pointer, size)
      width = get_mbchar_width(mbchar)
      byte_size = size
    else
      return [0, 0]
    end
    while (line.bytesize - 1) > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar =~ /\S/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    prev_width = width
    prev_byte_size = byte_size
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar =~ /\s/
      prev_width = width
      prev_byte_size = byte_size
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [prev_byte_size, prev_width]
  end

  def self.vi_big_backward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar =~ /\S/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      break if mbchar =~ /\s/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.vi_forward_word(line, byte_pointer)
    if (line.bytesize - 1) > byte_pointer
      size = get_next_mbchar_size(line, byte_pointer)
      mbchar = line.byteslice(byte_pointer, size)
      if mbchar =~ /\w/
        started_by = :word
      elsif mbchar =~ /\s/
        started_by = :space
      else
        started_by = :non_word_printable
      end
      width = get_mbchar_width(mbchar)
      byte_size = size
    else
      return [0, 0]
    end
    while (line.bytesize - 1) > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      case started_by
      when :word
        break if mbchar =~ /\W/
      when :space
        break if mbchar =~ /\S/
      when :non_word_printable
        break if mbchar =~ /\w|\s/
      end
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while (line.bytesize - 1) > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      break if mbchar =~ /\S/
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.vi_forward_end_word(line, byte_pointer)
    if (line.bytesize - 1) > byte_pointer
      size = get_next_mbchar_size(line, byte_pointer)
      mbchar = line.byteslice(byte_pointer, size)
      if mbchar =~ /\w/
        started_by = :word
      elsif mbchar =~ /\s/
        started_by = :space
      else
        started_by = :non_word_printable
      end
      width = get_mbchar_width(mbchar)
      byte_size = size
    else
      return [0, 0]
    end
    if (line.bytesize - 1) > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      if mbchar =~ /\w/
        second = :word
      elsif mbchar =~ /\s/
        second = :space
      else
        second = :non_word_printable
      end
      second_width = get_mbchar_width(mbchar)
      second_byte_size = size
    else
      return [byte_size, width]
    end
    if second == :space
      width += second_width
      byte_size += second_byte_size
      while (line.bytesize - 1) > (byte_pointer + byte_size)
        size = get_next_mbchar_size(line, byte_pointer + byte_size)
        mbchar = line.byteslice(byte_pointer + byte_size, size)
        if mbchar =~ /\S/
          if mbchar =~ /\w/
            started_by = :word
          else
            started_by = :non_word_printable
          end
          break
        end
        width += get_mbchar_width(mbchar)
        byte_size += size
      end
    else
      case [started_by, second]
      when [:word, :non_word_printable], [:non_word_printable, :word]
        started_by = second
      else
        width += second_width
        byte_size += second_byte_size
        started_by = second
      end
    end
    prev_width = width
    prev_byte_size = byte_size
    while line.bytesize > (byte_pointer + byte_size)
      size = get_next_mbchar_size(line, byte_pointer + byte_size)
      mbchar = line.byteslice(byte_pointer + byte_size, size)
      case started_by
      when :word
        break if mbchar =~ /\W/
      when :non_word_printable
        break if mbchar =~ /[\w\s]/
      end
      prev_width = width
      prev_byte_size = byte_size
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [prev_byte_size, prev_width]
  end

  def self.vi_backward_word(line, byte_pointer)
    width = 0
    byte_size = 0
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      if mbchar =~ /\S/
        if mbchar =~ /\w/
          started_by = :word
        else
          started_by = :non_word_printable
        end
        break
      end
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    while 0 < (byte_pointer - byte_size)
      size = get_prev_mbchar_size(line, byte_pointer - byte_size)
      mbchar = line.byteslice(byte_pointer - byte_size - size, size)
      case started_by
      when :word
        break if mbchar =~ /\W/
      when :non_word_printable
        break if mbchar =~ /[\w\s]/
      end
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end

  def self.vi_first_print(line)
    width = 0
    byte_size = 0
    while (line.bytesize - 1) > byte_size
      size = get_next_mbchar_size(line, byte_size)
      mbchar = line.byteslice(byte_size, size)
      if mbchar =~ /\S/
        break
      end
      width += get_mbchar_width(mbchar)
      byte_size += size
    end
    [byte_size, width]
  end
end

require 'reline/unicode/east_asian_width'
