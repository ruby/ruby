# frozen_string_literal: true
class CGI
  module Util; end
  include Util
  extend Util
end
module CGI::Util
  @@accept_charset="UTF-8" unless defined?(@@accept_charset)
  # URL-encode a string.
  #   url_encoded_string = CGI.escape("'Stop!' said Fred")
  #      # => "%27Stop%21%27+said+Fred"
  def escape(string)
    encoding = string.encoding
    string.b.gsub(/([^ a-zA-Z0-9_.\-~]+)/) do |m|
      '%' + m.unpack('H2' * m.bytesize).join('%').upcase
    end.tr(' ', '+').force_encoding(encoding)
  end

  # URL-decode a string with encoding(optional).
  #   string = CGI.unescape("%27Stop%21%27+said+Fred")
  #      # => "'Stop!' said Fred"
  def unescape(string,encoding=@@accept_charset)
    str=string.tr('+', ' ').b.gsub(/((?:%[0-9a-fA-F]{2})+)/) do |m|
      [m.delete('%')].pack('H*')
    end.force_encoding(encoding)
    str.valid_encoding? ? str : str.force_encoding(string.encoding)
  end

  # The set of special characters and their escaped values
  TABLE_FOR_ESCAPE_HTML__ = {
    "'" => '&#39;',
    '&' => '&amp;',
    '"' => '&quot;',
    '<' => '&lt;',
    '>' => '&gt;',
  }

  # Escape special characters in HTML, namely '&\"<>
  #   CGI.escapeHTML('Usage: foo "bar" <baz>')
  #      # => "Usage: foo &quot;bar&quot; &lt;baz&gt;"
  def escapeHTML(string)
    enc = string.encoding
    unless enc.ascii_compatible?
      if enc.dummy?
        origenc = enc
        enc = Encoding::Converter.asciicompat_encoding(enc)
        string = enc ? string.encode(enc) : string.b
      end
      table = Hash[TABLE_FOR_ESCAPE_HTML__.map {|pair|pair.map {|s|s.encode(enc)}}]
      string = string.gsub(/#{"['&\"<>]".encode(enc)}/, table)
      string.encode!(origenc) if origenc
      return string
    end
    string.gsub(/['&\"<>]/, TABLE_FOR_ESCAPE_HTML__)
  end

  begin
    require 'cgi/escape'
  rescue LoadError
  end

  # Unescape a string that has been HTML-escaped
  #   CGI.unescapeHTML("Usage: foo &quot;bar&quot; &lt;baz&gt;")
  #      # => "Usage: foo \"bar\" <baz>"
  def unescapeHTML(string)
    enc = string.encoding
    unless enc.ascii_compatible?
      if enc.dummy?
        origenc = enc
        enc = Encoding::Converter.asciicompat_encoding(enc)
        string = enc ? string.encode(enc) : string.b
      end
      string = string.gsub(Regexp.new('&(apos|amp|quot|gt|lt|#[0-9]+|#x[0-9A-Fa-f]+);'.encode(enc))) do
        case $1.encode(Encoding::US_ASCII)
        when 'apos'                then "'".encode(enc)
        when 'amp'                 then '&'.encode(enc)
        when 'quot'                then '"'.encode(enc)
        when 'gt'                  then '>'.encode(enc)
        when 'lt'                  then '<'.encode(enc)
        when /\A#0*(\d+)\z/        then $1.to_i.chr(enc)
        when /\A#x([0-9a-f]+)\z/i  then $1.hex.chr(enc)
        end
      end
      string.encode!(origenc) if origenc
      return string
    end
    return string unless string.include? '&'
    charlimit = case enc
                when Encoding::UTF_8; 0x10ffff
                when Encoding::ISO_8859_1; 256
                else 128
                end
    string.gsub(/&(apos|amp|quot|gt|lt|\#[0-9]+|\#[xX][0-9A-Fa-f]+);/) do
      match = $1.dup
      case match
      when 'apos'                then "'"
      when 'amp'                 then '&'
      when 'quot'                then '"'
      when 'gt'                  then '>'
      when 'lt'                  then '<'
      when /\A#0*(\d+)\z/
        n = $1.to_i
        if n < charlimit
          n.chr(enc)
        else
          "&##{$1};"
        end
      when /\A#x([0-9a-f]+)\z/i
        n = $1.hex
        if n < charlimit
          n.chr(enc)
        else
          "&#x#{$1};"
        end
      else
        "&#{match};"
      end
    end
  end

  # Synonym for CGI.escapeHTML(str)
  alias escape_html escapeHTML

  # Synonym for CGI.unescapeHTML(str)
  alias unescape_html unescapeHTML

  # Escape only the tags of certain HTML elements in +string+.
  #
  # Takes an element or elements or array of elements.  Each element
  # is specified by the name of the element, without angle brackets.
  # This matches both the start and the end tag of that element.
  # The attribute list of the open tag will also be escaped (for
  # instance, the double-quotes surrounding attribute values).
  #
  #   print CGI.escapeElement('<BR><A HREF="url"></A>', "A", "IMG")
  #     # "<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt"
  #
  #   print CGI.escapeElement('<BR><A HREF="url"></A>', ["A", "IMG"])
  #     # "<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt"
  def escapeElement(string, *elements)
    elements = elements[0] if elements[0].kind_of?(Array)
    unless elements.empty?
      string.gsub(/<\/?(?:#{elements.join("|")})(?!\w)(?:.|\n)*?>/i) do
        CGI.escapeHTML($&)
      end
    else
      string
    end
  end

  # Undo escaping such as that done by CGI.escapeElement()
  #
  #   print CGI.unescapeElement(
  #           CGI.escapeHTML('<BR><A HREF="url"></A>'), "A", "IMG")
  #     # "&lt;BR&gt;<A HREF="url"></A>"
  #
  #   print CGI.unescapeElement(
  #           CGI.escapeHTML('<BR><A HREF="url"></A>'), ["A", "IMG"])
  #     # "&lt;BR&gt;<A HREF="url"></A>"
  def unescapeElement(string, *elements)
    elements = elements[0] if elements[0].kind_of?(Array)
    unless elements.empty?
      string.gsub(/&lt;\/?(?:#{elements.join("|")})(?!\w)(?:.|\n)*?&gt;/i) do
        unescapeHTML($&)
      end
    else
      string
    end
  end

  # Synonym for CGI.escapeElement(str)
  alias escape_element escapeElement

  # Synonym for CGI.unescapeElement(str)
  alias unescape_element unescapeElement

  # Abbreviated day-of-week names specified by RFC 822
  RFC822_DAYS = %w[ Sun Mon Tue Wed Thu Fri Sat ]

  # Abbreviated month names specified by RFC 822
  RFC822_MONTHS = %w[ Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec ]

  # Format a +Time+ object as a String using the format specified by RFC 1123.
  #
  #   CGI.rfc1123_date(Time.now)
  #     # Sat, 01 Jan 2000 00:00:00 GMT
  def rfc1123_date(time)
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
  #   print CGI.pretty("<HTML><BODY></BODY></HTML>")
  #     # <HTML>
  #     #   <BODY>
  #     #   </BODY>
  #     # </HTML>
  #
  #   print CGI.pretty("<HTML><BODY></BODY></HTML>", "\t")
  #     # <HTML>
  #     #         <BODY>
  #     #         </BODY>
  #     # </HTML>
  #
  def pretty(string, shift = "  ")
    lines = string.gsub(/(?!\A)<.*?>/m, "\n\\0").gsub(/<.*?>(?!\n)/m, "\\0\n")
    end_pos = 0
    while end_pos = lines.index(/^<\/(\w+)/, end_pos)
      element = $1.dup
      start_pos = lines.rindex(/^\s*<#{element}/i, end_pos)
      lines[start_pos ... end_pos] = "__" + lines[start_pos ... end_pos].gsub(/\n(?!\z)/, "\n" + shift) + "__"
    end
    lines.gsub(/^((?:#{Regexp::quote(shift)})*)__(?=<\/?\w)/, '\1')
  end

  alias h escapeHTML
end
