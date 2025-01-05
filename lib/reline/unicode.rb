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
    0x1C => '^\\', # C-\
    0x1D => '^]', # C-]
    0x1E => '^^', # C-~ C-6
    0x1F => '^_', # C-_ C-7
    0x7F => '^?', # C-? C-8
  }

  NON_PRINTING_START = "\1"
  NON_PRINTING_END = "\2"
  CSI_REGEXP = /\e\[[\d;]*[ABCDEFGHJKSTfminsuhl]/
  OSC_REGEXP = /\e\]\d+(?:;[^;\a\e]+)*(?:\a|\e\\)/
  WIDTH_SCANNER = /\G(?:(#{NON_PRINTING_START})|(#{NON_PRINTING_END})|(#{CSI_REGEXP})|(#{OSC_REGEXP})|(\X))/o

  def self.escape_for_print(str)
    str.chars.map! { |gr|
      case gr
      when -"\n"
        gr
      when -"\t"
        -'  '
      else
        EscapedPairs[gr.ord] || gr
      end
    }.join
  end

  def self.safe_encode(str, encoding)
    # Reline only supports utf-8 convertible string.
    converted = str.encode(encoding, invalid: :replace, undef: :replace)
    return converted if str.encoding == Encoding::UTF_8 || converted.encoding == Encoding::UTF_8 || converted.ascii_only?

    # This code is essentially doing the same thing as
    # `str.encode(utf8, **replace_options).encode(encoding, **replace_options)`
    # but also avoids unnecessary irreversible encoding conversion.
    converted.gsub(/\X/) do |c|
      c.encode(Encoding::UTF_8)
      c
    rescue Encoding::UndefinedConversionError
      '?'
    end
  end

  require 'reline/unicode/east_asian_width'

  def self.get_mbchar_width(mbchar)
    ord = mbchar.ord
    if ord <= 0x1F # in EscapedPairs
      return 2
    elsif ord <= 0x7E # printable ASCII chars
      return 1
    end
    utf8_mbchar = mbchar.encode(Encoding::UTF_8)
    ord = utf8_mbchar.ord
    chunk_index = EastAsianWidth::CHUNK_LAST.bsearch_index { |o| ord <= o }
    size = EastAsianWidth::CHUNK_WIDTH[chunk_index]
    if size == -1
      Reline.ambiguous_width
    elsif size == 1 && utf8_mbchar.size >= 2
      second_char_ord = utf8_mbchar[1].ord
      # Halfwidth Dakuten Handakuten
      # Only these two character has Letter Modifier category and can be combined in a single grapheme cluster
      (second_char_ord == 0xFF9E || second_char_ord == 0xFF9F) ? 2 : 1
    else
      size
    end
  end

  def self.calculate_width(str, allow_escape_code = false)
    if allow_escape_code
      width = 0
      rest = str.encode(Encoding::UTF_8)
      in_zero_width = false
      rest.scan(WIDTH_SCANNER) do |non_printing_start, non_printing_end, csi, osc, gc|
        case
        when non_printing_start
          in_zero_width = true
        when non_printing_end
          in_zero_width = false
        when csi, osc
        when gc
          unless in_zero_width
            width += get_mbchar_width(gc)
          end
        end
      end
      width
    else
      str.encode(Encoding::UTF_8).grapheme_clusters.inject(0) { |w, gc|
        w + get_mbchar_width(gc)
      }
    end
  end

  # This method is used by IRB
  def self.split_by_width(str, max_width)
    lines = split_line_by_width(str, max_width)
    [lines, lines.size]
  end

  def self.split_line_by_width(str, max_width, encoding = str.encoding, offset: 0)
    lines = [String.new(encoding: encoding)]
    width = offset
    rest = str.encode(Encoding::UTF_8)
    in_zero_width = false
    seq = String.new(encoding: encoding)
    rest.scan(WIDTH_SCANNER) do |non_printing_start, non_printing_end, csi, osc, gc|
      case
      when non_printing_start
        in_zero_width = true
      when non_printing_end
        in_zero_width = false
      when csi
        lines.last << csi
        unless in_zero_width
          if csi == -"\e[m" || csi == -"\e[0m"
            seq.clear
          else
            seq << csi
          end
        end
      when osc
        lines.last << osc
        seq << osc unless in_zero_width
      when gc
        unless in_zero_width
          mbchar_width = get_mbchar_width(gc)
          if (width += mbchar_width) > max_width
            width = mbchar_width
            lines << seq.dup
          end
        end
        lines.last << gc
      end
    end
    # The cursor moves to next line in first
    if width == max_width
      lines << String.new(encoding: encoding)
    end
    lines
  end

  def self.strip_non_printing_start_end(prompt)
    prompt.gsub(/\x01([^\x02]*)(?:\x02|\z)/) { $1 }
  end

  # Take a chunk of a String cut by width with escape sequences.
  def self.take_range(str, start_col, max_width)
    take_mbchar_range(str, start_col, max_width).first
  end

  def self.take_mbchar_range(str, start_col, width, cover_begin: false, cover_end: false, padding: false)
    chunk = String.new(encoding: str.encoding)

    end_col = start_col + width
    total_width = 0
    rest = str.encode(Encoding::UTF_8)
    in_zero_width = false
    chunk_start_col = nil
    chunk_end_col = nil
    has_csi = false
    rest.scan(WIDTH_SCANNER) do |non_printing_start, non_printing_end, csi, osc, gc|
      case
      when non_printing_start
        in_zero_width = true
      when non_printing_end
        in_zero_width = false
      when csi
        has_csi = true
        chunk << csi
      when osc
        chunk << osc
      when gc
        if in_zero_width
          chunk << gc
          next
        end

        mbchar_width = get_mbchar_width(gc)
        prev_width = total_width
        total_width += mbchar_width

        if (cover_begin || padding ? total_width <= start_col : prev_width < start_col)
          # Current character haven't reached start_col yet
          next
        elsif padding && !cover_begin && prev_width < start_col && start_col < total_width
          # Add preceding padding. This padding might have background color.
          chunk << ' '
          chunk_start_col ||= start_col
          chunk_end_col = total_width
          next
        elsif (cover_end ? prev_width < end_col : total_width <= end_col)
          # Current character is in the range
          chunk << gc
          chunk_start_col ||= prev_width
          chunk_end_col = total_width
          break if total_width >= end_col
        else
          # Current character exceeds end_col
          if padding && end_col < total_width
            # Add succeeding padding. This padding might have background color.
            chunk << ' '
            chunk_start_col ||= prev_width
            chunk_end_col = end_col
          end
          break
        end
      end
    end
    chunk_start_col ||= start_col
    chunk_end_col ||= start_col
    if padding && chunk_end_col < end_col
      # Append padding. This padding should not include background color.
      chunk << "\e[0m" if has_csi
      chunk << ' ' * (end_col - chunk_end_col)
      chunk_end_col = end_col
    end
    [chunk, chunk_start_col, chunk_end_col - chunk_start_col]
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
    gcs = line.byteslice(byte_pointer..).grapheme_clusters
    nonwords = gcs.take_while { |c| !word_character?(c) }
    words = gcs.drop(nonwords.size).take_while { |c| word_character?(c) }
    nonwords.sum(&:bytesize) + words.sum(&:bytesize)
  end

  def self.em_forward_word_with_capitalization(line, byte_pointer)
    gcs = line.byteslice(byte_pointer..).grapheme_clusters
    nonwords = gcs.take_while { |c| !word_character?(c) }
    words = gcs.drop(nonwords.size).take_while { |c| word_character?(c) }
    [nonwords.sum(&:bytesize) + words.sum(&:bytesize), nonwords.join + words.join.capitalize]
  end

  def self.em_backward_word(line, byte_pointer)
    gcs = line.byteslice(0, byte_pointer).grapheme_clusters.reverse
    nonwords = gcs.take_while { |c| !word_character?(c) }
    words = gcs.drop(nonwords.size).take_while { |c| word_character?(c) }
    nonwords.sum(&:bytesize) + words.sum(&:bytesize)
  end

  def self.em_big_backward_word(line, byte_pointer)
    gcs = line.byteslice(0, byte_pointer).grapheme_clusters.reverse
    spaces = gcs.take_while { |c| space_character?(c) }
    nonspaces = gcs.drop(spaces.size).take_while { |c| !space_character?(c) }
    spaces.sum(&:bytesize) + nonspaces.sum(&:bytesize)
  end

  def self.ed_transpose_words(line, byte_pointer)
    gcs = line.byteslice(0, byte_pointer).grapheme_clusters
    pos = gcs.size
    gcs += line.byteslice(byte_pointer..).grapheme_clusters
    pos += 1 while pos < gcs.size && !word_character?(gcs[pos])
    if pos == gcs.size # 'aaa  bbb [cursor] '
      pos -= 1 while pos > 0 && !word_character?(gcs[pos - 1])
      second_word_end = gcs.size
    else # 'aaa  [cursor]bbb'
      pos += 1 while pos < gcs.size && word_character?(gcs[pos])
      second_word_end = pos
    end
    pos -= 1 while pos > 0 && word_character?(gcs[pos - 1])
    second_word_start = pos
    pos -= 1 while pos > 0 && !word_character?(gcs[pos - 1])
    first_word_end = pos
    pos -= 1 while pos > 0 && word_character?(gcs[pos - 1])
    first_word_start = pos

    [first_word_start, first_word_end, second_word_start, second_word_end].map do |idx|
      gcs.take(idx).sum(&:bytesize)
    end
  end

  def self.vi_big_forward_word(line, byte_pointer)
    gcs = line.byteslice(byte_pointer..).grapheme_clusters
    nonspaces = gcs.take_while { |c| !space_character?(c) }
    spaces = gcs.drop(nonspaces.size).take_while { |c| space_character?(c) }
    nonspaces.sum(&:bytesize) + spaces.sum(&:bytesize)
  end

  def self.vi_big_forward_end_word(line, byte_pointer)
    gcs = line.byteslice(byte_pointer..).grapheme_clusters
    first = gcs.shift(1)
    spaces = gcs.take_while { |c| space_character?(c) }
    nonspaces = gcs.drop(spaces.size).take_while { |c| !space_character?(c) }
    matched = spaces + nonspaces
    matched.pop
    first.sum(&:bytesize) + matched.sum(&:bytesize)
  end

  def self.vi_big_backward_word(line, byte_pointer)
    gcs = line.byteslice(0, byte_pointer).grapheme_clusters.reverse
    spaces = gcs.take_while { |c| space_character?(c) }
    nonspaces = gcs.drop(spaces.size).take_while { |c| !space_character?(c) }
    spaces.sum(&:bytesize) + nonspaces.sum(&:bytesize)
  end

  def self.vi_forward_word(line, byte_pointer, drop_terminate_spaces = false)
    gcs = line.byteslice(byte_pointer..).grapheme_clusters
    return 0 if gcs.empty?

    c = gcs.first
    matched =
      if word_character?(c)
        gcs.take_while { |c| word_character?(c) }
      elsif space_character?(c)
        gcs.take_while { |c| space_character?(c) }
      else
        gcs.take_while { |c| !word_character?(c) && !space_character?(c) }
      end

    return matched.sum(&:bytesize) if drop_terminate_spaces

    spaces = gcs.drop(matched.size).take_while { |c| space_character?(c) }
    matched.sum(&:bytesize) + spaces.sum(&:bytesize)
  end

  def self.vi_forward_end_word(line, byte_pointer)
    gcs = line.byteslice(byte_pointer..).grapheme_clusters
    return 0 if gcs.empty?
    return gcs.first.bytesize if gcs.size == 1

    start = gcs.shift
    skips = [start]
    if space_character?(start) || space_character?(gcs.first)
      spaces = gcs.take_while { |c| space_character?(c) }
      skips += spaces
      gcs.shift(spaces.size)
    end
    start_with_word = word_character?(gcs.first)
    matched = gcs.take_while { |c| start_with_word ? word_character?(c) : !word_character?(c) && !space_character?(c) }
    matched.pop
    skips.sum(&:bytesize) + matched.sum(&:bytesize)
  end

  def self.vi_backward_word(line, byte_pointer)
    gcs = line.byteslice(0, byte_pointer).grapheme_clusters.reverse
    spaces = gcs.take_while { |c| space_character?(c) }
    gcs.shift(spaces.size)
    start_with_word = word_character?(gcs.first)
    matched = gcs.take_while { |c| start_with_word ? word_character?(c) : !word_character?(c) && !space_character?(c) }
    spaces.sum(&:bytesize) + matched.sum(&:bytesize)
  end

  def self.common_prefix(list, ignore_case: false)
    return '' if list.empty?

    common_prefix_gcs = list.first.grapheme_clusters
    list.each do |item|
      gcs = item.grapheme_clusters
      common_prefix_gcs = common_prefix_gcs.take_while.with_index do |gc, i|
        ignore_case ? gc.casecmp?(gcs[i]) : gc == gcs[i]
      end
    end
    common_prefix_gcs.join
  end

  def self.vi_first_print(line)
    gcs = line.grapheme_clusters
    spaces = gcs.take_while { |c| space_character?(c) }
    spaces.sum(&:bytesize)
  end

  def self.word_character?(s)
    s.encode(Encoding::UTF_8).match?(/\p{Word}/) if s
  rescue Encoding::UndefinedConversionError
    false
  end

  def self.space_character?(s)
    s.match?(/\s/) if s
  end
end
