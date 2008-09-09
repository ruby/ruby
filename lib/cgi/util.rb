class CGI
  # URL-encode a string.
  #   url_encoded_string = CGI::escape("'Stop!' said Fred")
  #      # => "%27Stop%21%27+said+Fred"
  def CGI::escape(string)
    string.gsub(/([^ a-zA-Z0-9_.-]+)/) do
      '%' + $1.unpack('H2' * $1.bytesize).join('%').upcase
    end.tr(' ', '+')
  end


  # URL-decode a string.
  #   string = CGI::unescape("%27Stop%21%27+said+Fred")
  #      # => "'Stop!' said Fred"
  def CGI::unescape(string)
    enc = string.encoding
    string.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/) do
      [$1.delete('%')].pack('H*').force_encoding(enc)
    end
  end

  TABLE_FOR_ESCAPE_HTML__ = {
    '&' => '&amp;',
    '"' => '&quot;',
    '<' => '&lt;',
    '>' => '&gt;',
  }

  # Escape special characters in HTML, namely &\"<>
  #   CGI::escapeHTML('Usage: foo "bar" <baz>')
  #      # => "Usage: foo &quot;bar&quot; &lt;baz&gt;"
  def CGI::escapeHTML(string)
    string.gsub(/[&\"<>]/, TABLE_FOR_ESCAPE_HTML__)
  end


  # Unescape a string that has been HTML-escaped
  #   CGI::unescapeHTML("Usage: foo &quot;bar&quot; &lt;baz&gt;")
  #      # => "Usage: foo \"bar\" <baz>"
  def CGI::unescapeHTML(string)
    enc = string.encoding
    if [Encoding::UTF_16BE, Encoding::UTF_16LE, Encoding::UTF_32BE, Encoding::UTF_32LE].include?(enc)
      return string.gsub(Regexp.new('&(amp|quot|gt|lt|#[0-9]+|#x[0-9A-Fa-f]+);'.encode(enc))) do
        case $1.encode("US-ASCII")
        when 'amp'                 then '&'.encode(enc)
        when 'quot'                then '"'.encode(enc)
        when 'gt'                  then '>'.encode(enc)
        when 'lt'                  then '<'.encode(enc)
        when /\A#0*(\d+)\z/        then $1.to_i.chr(enc)
        when /\A#x([0-9a-f]+)\z/i  then $1.hex.chr(enc)
        end
      end
    end
    asciicompat = Encoding.compatible?(string, "a")
    string.gsub(/&(amp|quot|gt|lt|\#[0-9]+|\#x[0-9A-Fa-f]+);/) do
      match = $1.dup
      case match
      when 'amp'                 then '&'
      when 'quot'                then '"'
      when 'gt'                  then '>'
      when 'lt'                  then '<'
      when /\A#0*(\d+)\z/
        n = $1.to_i
        if enc == Encoding::UTF_8 or
          enc == Encoding::ISO_8859_1 && n < 256 or
          asciicompat && n < 128
          n.chr(enc)
        else
          "&##{$1};"
        end
      when /\A#x([0-9a-f]+)\z/i
        n = $1.hex
        if enc == Encoding::UTF_8 or
          enc == Encoding::ISO_8859_1 && n < 256 or
          asciicompat && n < 128
          n.chr(enc)
        else
          "&#x#{$1};"
        end
      else
        "&#{match};"
      end
    end
  end
  def CGI::escape_html(str)
    escapeHTML(str)
  end
  def CGI::unescape_html(str)
    unescapeHTML(str)
  end

  # Escape only the tags of certain HTML elements in +string+.
  #
  # Takes an element or elements or array of elements.  Each element
  # is specified by the name of the element, without angle brackets.
  # This matches both the start and the end tag of that element.
  # The attribute list of the open tag will also be escaped (for
  # instance, the double-quotes surrounding attribute values).
  #
  #   print CGI::escapeElement('<BR><A HREF="url"></A>', "A", "IMG")
  #     # "<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt"
  #
  #   print CGI::escapeElement('<BR><A HREF="url"></A>', ["A", "IMG"])
  #     # "<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt"
  def CGI::escapeElement(string, *elements)
    elements = elements[0] if elements[0].kind_of?(Array)
    unless elements.empty?
      string.gsub(/<\/?(?:#{elements.join("|")})(?!\w)(?:.|\n)*?>/i) do
        CGI::escapeHTML($&)
      end
    else
      string
    end
  end


  # Undo escaping such as that done by CGI::escapeElement()
  #
  #   print CGI::unescapeElement(
  #           CGI::escapeHTML('<BR><A HREF="url"></A>'), "A", "IMG")
  #     # "&lt;BR&gt;<A HREF="url"></A>"
  # 
  #   print CGI::unescapeElement(
  #           CGI::escapeHTML('<BR><A HREF="url"></A>'), ["A", "IMG"])
  #     # "&lt;BR&gt;<A HREF="url"></A>"
  def CGI::unescapeElement(string, *elements)
    elements = elements[0] if elements[0].kind_of?(Array)
    unless elements.empty?
      string.gsub(/&lt;\/?(?:#{elements.join("|")})(?!\w)(?:.|\n)*?&gt;/i) do
        CGI::unescapeHTML($&)
      end
    else
      string
    end
  end
  def CGI::escape_element(str)
    escapeElement(str)
  end
  def CGI::unescape_element(str)
    unescapeElement(str)
  end

  # Format a +Time+ object as a String using the format specified by RFC 1123.
  #
  #   CGI::rfc1123_date(Time.now)
  #     # Sat, 01 Jan 2000 00:00:00 GMT
  def CGI::rfc1123_date(time)
    t = time.clone.gmtime
    return format("%s, %.2d %s %.4d %.2d:%.2d:%.2d GMT",
                RFC822_DAYS[t.wday], t.day, RFC822_MONTHS[t.month-1], t.year,
                t.hour, t.min, t.sec)
  end

  # Prettify (indent) an HTML string.
  #
  # +string+ is the HTML string to indent.  +shift+ is the indentation
  # unit to use; it defaults to two spaces.
  #
  #   print CGI::pretty("<HTML><BODY></BODY></HTML>")
  #     # <HTML>
  #     #   <BODY>
  #     #   </BODY>
  #     # </HTML>
  # 
  #   print CGI::pretty("<HTML><BODY></BODY></HTML>", "\t")
  #     # <HTML>
  #     #         <BODY>
  #     #         </BODY>
  #     # </HTML>
  #
  def CGI::pretty(string, shift = "  ")
    lines = string.gsub(/(?!\A)<(?:.|\n)*?>/, "\n\\0").gsub(/<(?:.|\n)*?>(?!\n)/, "\\0\n")
    end_pos = 0
    while end_pos = lines.index(/^<\/(\w+)/, end_pos)
      element = $1.dup
      start_pos = lines.rindex(/^\s*<#{element}/i, end_pos)
      lines[start_pos ... end_pos] = "__" + lines[start_pos ... end_pos].gsub(/\n(?!\z)/, "\n" + shift) + "__"
    end
    lines.gsub(/^((?:#{Regexp::quote(shift)})*)__(?=<\/?\w)/, '\1')
  end
end
