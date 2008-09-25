require 'rdoc/markup/formatter'
require 'rdoc/markup/fragments'
require 'rdoc/markup/inline'

require 'cgi'

class RDoc::Markup::ToHtml < RDoc::Markup::Formatter

  LIST_TYPE_TO_HTML = {
    :BULLET =>     %w[<ul> </ul>],
    :NUMBER =>     %w[<ol> </ol>],
    :UPPERALPHA => %w[<ol> </ol>],
    :LOWERALPHA => %w[<ol> </ol>],
    :LABELED =>    %w[<dl> </dl>],
    :NOTE    =>    %w[<table> </table>],
  }

  InlineTag = Struct.new(:bit, :on, :off)

  def initialize
    super

    # @in_tt - tt nested levels count
    # @tt_bit - cache
    @in_tt = 0
    @tt_bit = RDoc::Markup::Attribute.bitmap_for :TT

    # external hyperlinks
    @markup.add_special(/((link:|https?:|mailto:|ftp:|www\.)\S+\w)/, :HYPERLINK)

    # and links of the form  <text>[<url>]
    @markup.add_special(/(((\{.*?\})|\b\S+?)\[\S+?\.\S+?\])/, :TIDYLINK)

    init_tags
  end

  ##
  # Converts a target url to one that is relative to a given path

  def self.gen_relative_url(path, target)
    from        = File.dirname path
    to, to_file = File.split target

    from = from.split "/"
    to   = to.split "/"

    while from.size > 0 and to.size > 0 and from[0] == to[0] do
      from.shift
      to.shift
    end

    from.fill ".."
    from.concat to
    from << to_file
    File.join(*from)
  end

  ##
  # Generate a hyperlink for url, labeled with text. Handle the
  # special cases for img: and link: described under handle_special_HYPERLINK

  def gen_url(url, text)
    if url =~ /([A-Za-z]+):(.*)/ then
      type = $1
      path = $2
    else
      type = "http"
      path = url
      url  = "http://#{url}"
    end

    if type == "link" then
      url = if path[0, 1] == '#' then # is this meaningful?
              path
            else
              self.class.gen_relative_url @from_path, path
            end
    end

    if (type == "http" or type == "link") and
       url =~ /\.(gif|png|jpg|jpeg|bmp)$/ then
      "<img src=\"#{url}\" />"
    else
      "<a href=\"#{url}\">#{text.sub(%r{^#{type}:/*}, '')}</a>"
    end
  end

  ##
  # And we're invoked with a potential external hyperlink mailto:
  # just gets inserted. http: links are checked to see if they
  # reference an image. If so, that image gets inserted using an
  # <img> tag. Otherwise a conventional <a href> is used.  We also
  # support a special type of hyperlink, link:, which is a reference
  # to a local file whose path is relative to the --op directory.

  def handle_special_HYPERLINK(special)
    url = special.text
    gen_url url, url
  end

  ##
  # Here's a hypedlink where the label is different to the URL
  #  <label>[url] or {long label}[url]

  def handle_special_TIDYLINK(special)
    text = special.text

    return text unless text =~ /\{(.*?)\}\[(.*?)\]/ or text =~ /(\S+)\[(.*?)\]/

    label = $1
    url   = $2
    gen_url url, label
  end

  ##
  # are we currently inside <tt> tags?

  def in_tt?
    @in_tt > 0
  end

  ##
  # is +tag+ a <tt> tag?

  def tt?(tag)
    tag.bit == @tt_bit
  end

  ##
  # Set up the standard mapping of attributes to HTML tags

  def init_tags
    @attr_tags = [
      InlineTag.new(RDoc::Markup::Attribute.bitmap_for(:BOLD), "<b>", "</b>"),
      InlineTag.new(RDoc::Markup::Attribute.bitmap_for(:TT),   "<tt>", "</tt>"),
      InlineTag.new(RDoc::Markup::Attribute.bitmap_for(:EM),   "<em>", "</em>"),
    ]
  end

  ##
  # Add a new set of HTML tags for an attribute. We allow separate start and
  # end tags for flexibility.

  def add_tag(name, start, stop)
    @attr_tags << InlineTag.new(RDoc::Markup::Attribute.bitmap_for(name), start, stop)
  end

  ##
  # Given an HTML tag, decorate it with class information and the like if
  # required. This is a no-op in the base class, but is overridden in HTML
  # output classes that implement style sheets.

  def annotate(tag)
    tag
  end

  ##
  # Here's the client side of the visitor pattern

  def start_accepting
    @res = ""
    @in_list_entry = []
  end

  def end_accepting
    @res
  end

  def accept_paragraph(am, fragment)
    @res << annotate("<p>") + "\n"
    @res << wrap(convert_flow(am.flow(fragment.txt)))
    @res << annotate("</p>") + "\n"
  end

  def accept_verbatim(am, fragment)
    @res << annotate("<pre>") + "\n"
    @res << CGI.escapeHTML(fragment.txt)
    @res << annotate("</pre>") << "\n"
  end

  def accept_rule(am, fragment)
    size = fragment.param
    size = 10 if size > 10
    @res << "<hr size=\"#{size}\"></hr>"
  end

  def accept_list_start(am, fragment)
    @res << html_list_name(fragment.type, true) << "\n"
    @in_list_entry.push false
  end

  def accept_list_end(am, fragment)
    if tag = @in_list_entry.pop
      @res << annotate(tag) << "\n"
    end
    @res << html_list_name(fragment.type, false) << "\n"
  end

  def accept_list_item(am, fragment)
    if tag = @in_list_entry.last
      @res << annotate(tag) << "\n"
    end

    @res << list_item_start(am, fragment)

    @res << wrap(convert_flow(am.flow(fragment.txt))) << "\n"

    @in_list_entry[-1] = list_end_for(fragment.type)
  end

  def accept_blank_line(am, fragment)
    # @res << annotate("<p />") << "\n"
  end

  def accept_heading(am, fragment)
    @res << convert_heading(fragment.head_level, am.flow(fragment.txt))
  end

  ##
  # This is a higher speed (if messier) version of wrap

  def wrap(txt, line_len = 76)
    res = ""
    sp = 0
    ep = txt.length
    while sp < ep
      # scan back for a space
      p = sp + line_len - 1
      if p >= ep
        p = ep
      else
        while p > sp and txt[p] != ?\s
          p -= 1
        end
        if p <= sp
          p = sp + line_len
          while p < ep and txt[p] != ?\s
            p += 1
          end
        end
      end
      res << txt[sp...p] << "\n"
      sp = p
      sp += 1 while sp < ep and txt[sp] == ?\s
    end
    res
  end

  private

  def on_tags(res, item)
    attr_mask = item.turn_on
    return if attr_mask.zero?

    @attr_tags.each do |tag|
      if attr_mask & tag.bit != 0
        res << annotate(tag.on)
        @in_tt += 1 if tt?(tag)
      end
    end
  end

  def off_tags(res, item)
    attr_mask = item.turn_off
    return if attr_mask.zero?

    @attr_tags.reverse_each do |tag|
      if attr_mask & tag.bit != 0
        @in_tt -= 1 if tt?(tag)
        res << annotate(tag.off)
      end
    end
  end

  def convert_flow(flow)
    res = ""

    flow.each do |item|
      case item
      when String
        res << convert_string(item)
      when RDoc::Markup::AttrChanger
        off_tags(res, item)
        on_tags(res,  item)
      when RDoc::Markup::Special
        res << convert_special(item)
      else
        raise "Unknown flow element: #{item.inspect}"
      end
    end

    res
  end

  def convert_string(item)
    in_tt? ? convert_string_simple(item) : convert_string_fancy(item)
  end

  def convert_string_simple(item)
    CGI.escapeHTML item
  end

  ##
  # some of these patterns are taken from SmartyPants...

  def convert_string_fancy(item)
    # convert ampersand before doing anything else
    item.gsub(/&/, '&amp;').

    # convert -- to em-dash, (-- to en-dash)
      gsub(/---?/, '&#8212;'). #gsub(/--/, '&#8211;').
      
    # convert ... to elipsis (and make sure .... becomes .<elipsis>)
      gsub(/\.\.\.\./, '.&#8230;').gsub(/\.\.\./, '&#8230;').

    # convert single closing quote
      gsub(%r{([^ \t\r\n\[\{\(])\'}, '\1&#8217;'). # }
      gsub(%r{\'(?=\W|s\b)}, '&#8217;').

    # convert single opening quote
      gsub(/'/, '&#8216;').

    # convert double closing quote
      gsub(%r{([^ \t\r\n\[\{\(])\"(?=\W)}, '\1&#8221;'). # }

    # convert double opening quote
      gsub(/"/, '&#8220;').

    # convert copyright
      gsub(/\(c\)/, '&#169;').

    # convert registered trademark
      gsub(/\(r\)/, '&#174;')
  end

  def convert_special(special)
    handled = false
    RDoc::Markup::Attribute.each_name_of(special.type) do |name|
      method_name = "handle_special_#{name}"
      if self.respond_to? method_name
        special.text = send(method_name, special)
        handled = true
      end
    end
    raise "Unhandled special: #{special}" unless handled
    special.text
  end

  def convert_heading(level, flow)
    res =
      annotate("<h#{level}>") +
      convert_flow(flow) +
      annotate("</h#{level}>\n")
  end

  def html_list_name(list_type, is_open_tag)
    tags = LIST_TYPE_TO_HTML[list_type] || raise("Invalid list type: #{list_type.inspect}")
    annotate(tags[ is_open_tag ? 0 : 1])
  end

  def list_item_start(am, fragment)
    case fragment.type
    when :BULLET, :NUMBER then
      annotate("<li>")

    when :UPPERALPHA then
      annotate("<li type=\"A\">")

    when :LOWERALPHA then
      annotate("<li type=\"a\">")

    when :LABELED then
      annotate("<dt>") +
        convert_flow(am.flow(fragment.param)) +
        annotate("</dt>") +
        annotate("<dd>")

    when :NOTE then
      annotate("<tr>") +
        annotate("<td valign=\"top\">") +
        convert_flow(am.flow(fragment.param)) +
        annotate("</td>") +
        annotate("<td>")
    else
      raise "Invalid list type"
    end
  end

  def list_end_for(fragment_type)
    case fragment_type
    when :BULLET, :NUMBER, :UPPERALPHA, :LOWERALPHA then
      "</li>"
    when :LABELED then
      "</dd>"
    when :NOTE then
      "</td></tr>"
    else
      raise "Invalid list type"
    end
  end

end

