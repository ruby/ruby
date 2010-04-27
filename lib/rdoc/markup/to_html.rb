require 'rdoc/markup/formatter'
require 'rdoc/markup/inline'

require 'cgi'

##
# Outputs RDoc markup as HTML

class RDoc::Markup::ToHtml < RDoc::Markup::Formatter

  ##
  # Maps RDoc::Markup::Parser::LIST_TOKENS types to HTML tags

  LIST_TYPE_TO_HTML = {
    :BULLET => ['<ul>', '</ul>'],
    :LABEL  => ['<dl>', '</dl>'],
    :LALPHA => ['<ol style="display: lower-alpha">', '</ol>'],
    :NOTE   => ['<table>', '</table>'],
    :NUMBER => ['<ol>', '</ol>'],
    :UALPHA => ['<ol style="display: upper-alpha">', '</ol>'],
  }

  attr_reader :res # :nodoc:
  attr_reader :in_list_entry # :nodoc:
  attr_reader :list # :nodoc:

  ##
  # Converts a target url to one that is relative to a given path

  def self.gen_relative_url(path, target)
    from        = File.dirname path
    to, to_file = File.split target

    from = from.split "/"
    to   = to.split "/"

    from.delete '.'
    to.delete '.'

    while from.size > 0 and to.size > 0 and from[0] == to[0] do
      from.shift
      to.shift
    end

    from.fill ".."
    from.concat to
    from << to_file
    File.join(*from)
  end

  def initialize
    super

    @th = nil
    @in_list_entry = nil
    @list = nil

    # external hyperlinks
    @markup.add_special(/((link:|https?:|mailto:|ftp:|www\.)\S+\w)/, :HYPERLINK)

    # and links of the form  <text>[<url>]
    @markup.add_special(/(((\{.*?\})|\b\S+?)\[\S+?\.\S+?\])/, :TIDYLINK)

    init_tags
  end

  ##
  # Maps attributes to HTML tags

  def init_tags
    add_tag :BOLD, "<b>",  "</b>"
    add_tag :TT,   "<tt>", "</tt>"
    add_tag :EM,   "<em>", "</em>"
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
  # This is a higher speed (if messier) version of wrap

  def wrap(txt, line_len = 76)
    res = []
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

    res.join
  end

  ##
  # :section: Visitor

  def start_accepting
    @res = []
    @in_list_entry = []
    @list = []
  end

  def end_accepting
    @res.join
  end

  def accept_paragraph(paragraph)
    @res << annotate("<p>") + "\n"
    @res << wrap(convert_flow(@am.flow(paragraph.text)))
    @res << annotate("</p>") + "\n"
  end

  def accept_verbatim(verbatim)
    @res << annotate("<pre>") << "\n"
    @res << CGI.escapeHTML(verbatim.text)
    @res << annotate("</pre>") << "\n"
  end

  def accept_rule(rule)
    size = rule.weight
    size = 10 if size > 10
    @res << "<hr style=\"height: #{size}px\"></hr>"
  end

  def accept_list_start(list)
    @list << list.type
    @res << html_list_name(list.type, true) << "\n"
    @in_list_entry.push false
  end

  def accept_list_end(list)
    @list.pop
    if tag = @in_list_entry.pop
      @res << annotate(tag) << "\n"
    end
    @res << html_list_name(list.type, false) << "\n"
  end

  def accept_list_item_start(list_item)
    if tag = @in_list_entry.last
      @res << annotate(tag) << "\n"
    end

    @res << list_item_start(list_item, @list.last)
  end

  def accept_list_item_end(list_item)
    @in_list_entry[-1] = list_end_for(@list.last)
  end

  def accept_blank_line(blank_line)
    # @res << annotate("<p />") << "\n"
  end

  def accept_heading(heading)
    @res << convert_heading(heading.level, @am.flow(heading.text))
  end

  def accept_raw raw
    @res << raw.parts.join("\n")
  end

  private

  ##
  # Converts string +item+

  def convert_string(item)
    in_tt? ? convert_string_simple(item) : convert_string_fancy(item)
  end

  ##
  # Escapes HTML in +item+

  def convert_string_simple(item)
    CGI.escapeHTML item
  end

  ##
  # Converts ampersand, dashes, elipsis, quotes, copyright and registered
  # trademark symbols to HTML escaped Unicode.

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

  ##
  # Converts headings to hN elements

  def convert_heading(level, flow)
    [annotate("<h#{level}>"),
     convert_flow(flow),
     annotate("</h#{level}>\n")].join
  end

  ##
  # Determins the HTML list element for +list_type+ and +open_tag+

  def html_list_name(list_type, open_tag)
    tags = LIST_TYPE_TO_HTML[list_type]
    raise RDoc::Error, "Invalid list type: #{list_type.inspect}" unless tags
    annotate tags[open_tag ? 0 : 1]
  end

  ##
  # Starts a list item

  def list_item_start(list_item, list_type)
    case list_type
    when :BULLET, :LALPHA, :NUMBER, :UALPHA then
      annotate("<li>")

    when :LABEL then
      annotate("<dt>") +
        convert_flow(@am.flow(list_item.label)) +
        annotate("</dt>") +
        annotate("<dd>")

    when :NOTE then
      annotate("<tr>") +
        annotate("<td valign=\"top\">") +
        convert_flow(@am.flow(list_item.label)) +
        annotate("</td>") +
        annotate("<td>")
    else
      raise RDoc::Error, "Invalid list type: #{list_type.inspect}"
    end
  end

  ##
  # Ends a list item

  def list_end_for(list_type)
    case list_type
    when :BULLET, :LALPHA, :NUMBER, :UALPHA then
      "</li>"
    when :LABEL then
      "</dd>"
    when :NOTE then
      "</td></tr>"
    else
      raise RDoc::Error, "Invalid list type: #{list_type.inspect}"
    end
  end

end

