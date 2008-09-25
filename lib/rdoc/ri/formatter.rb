require 'rdoc/ri'
require 'rdoc/markup'

class RDoc::RI::Formatter

  attr_writer :indent
  attr_accessor :output

  FORMATTERS = { }

  def self.for(name)
    FORMATTERS[name.downcase]
  end

  def self.list
    FORMATTERS.keys.sort.join ", "
  end

  def initialize(output, width, indent)
    @output = output
    @width  = width
    @indent = indent
    @original_indent = indent.dup
  end

  def draw_line(label=nil)
    len = @width
    len -= (label.size + 1) if label

    if len > 0 then
      @output.print '-' * len
      if label
        @output.print ' '
        bold_print label
      end

      @output.puts
    else
      @output.print '-' * @width
      @output.puts

      @output.puts label
    end
  end

  def indent
    return @indent unless block_given?

    begin
      indent = @indent.dup
      @indent += @original_indent
      yield
    ensure
      @indent = indent
    end
  end

  def wrap(txt, prefix=@indent, linelen=@width)
    return unless txt && !txt.empty?

    work = conv_markup(txt)
    textLen = linelen - prefix.length
    patt = Regexp.new("^(.{0,#{textLen}})[ \n]")
    next_prefix = prefix.tr("^ ", " ")

    res = []

    while work.length > textLen
      if work =~ patt
        res << $1
        work.slice!(0, $&.length)
      else
        res << work.slice!(0, textLen)
      end
    end
    res << work if work.length.nonzero?
    @output.puts(prefix + res.join("\n" + next_prefix))
  end

  def blankline
    @output.puts
  end

  ##
  # Called when we want to ensure a new 'wrap' starts on a newline.  Only
  # needed for HtmlFormatter, because the rest do their own line breaking.

  def break_to_newline
  end

  def bold_print(txt)
    @output.print txt
  end

  def raw_print_line(txt)
    @output.print txt
  end

  ##
  # Convert HTML entities back to ASCII

  def conv_html(txt)
    txt = txt.gsub(/&gt;/, '>')
    txt.gsub!(/&lt;/, '<')
    txt.gsub!(/&quot;/, '"')
    txt.gsub!(/&amp;/, '&')
    txt
  end

  ##
  # Convert markup into display form

  def conv_markup(txt)
    txt = txt.gsub(%r{<tt>(.*?)</tt>}, '+\1+')
    txt.gsub!(%r{<code>(.*?)</code>}, '+\1+')
    txt.gsub!(%r{<b>(.*?)</b>}, '*\1*')
    txt.gsub!(%r{<em>(.*?)</em>}, '_\1_') 
    txt
  end

  def display_list(list)
    case list.type
    when :BULLET
      prefixer = proc { |ignored| @indent + "*   " }

    when :NUMBER, :UPPERALPHA, :LOWERALPHA then
      start = case list.type
              when :NUMBER     then 1
              when :UPPERALPHA then 'A'
              when :LOWERALPHA then 'a'
              end

      prefixer = proc do |ignored|
        res = @indent + "#{start}.".ljust(4)
        start = start.succ
        res
      end

    when :LABELED, :NOTE then
      longest = 0

      list.contents.each do |item|
        if RDoc::Markup::Flow::LI === item and item.label.length > longest then
          longest = item.label.length
        end
      end

      longest += 1

      prefixer = proc { |li| @indent + li.label.ljust(longest) }

    else
      raise ArgumentError, "unknown list type #{list.type}"
    end

    list.contents.each do |item|
      if RDoc::Markup::Flow::LI === item then
        prefix = prefixer.call item
        display_flow_item item, prefix
      else
        display_flow_item item
      end
    end
  end

  def display_flow_item(item, prefix = @indent)
    case item
    when RDoc::Markup::Flow::P, RDoc::Markup::Flow::LI
      wrap(conv_html(item.body), prefix)
      blankline

    when RDoc::Markup::Flow::LIST
      display_list(item)

    when RDoc::Markup::Flow::VERB
      display_verbatim_flow_item(item, @indent)

    when RDoc::Markup::Flow::H
      display_heading(conv_html(item.text), item.level, @indent)

    when RDoc::Markup::Flow::RULE
      draw_line

    else
      raise RDoc::Error, "Unknown flow element: #{item.class}"
    end
  end

  def display_verbatim_flow_item(item, prefix=@indent)
    item.body.split(/\n/).each do |line|
      @output.print @indent, conv_html(line), "\n"
    end
    blankline
  end

  def display_heading(text, level, indent)
    text = strip_attributes text

    case level
    when 1 then
      ul = "=" * text.length
      @output.puts
      @output.puts text.upcase
      @output.puts ul

    when 2 then
      ul = "-" * text.length
      @output.puts
      @output.puts text
      @output.puts ul
    else
      @output.print indent, text, "\n"
    end

    @output.puts
  end

  def display_flow(flow)
    flow.each do |f|
      display_flow_item(f)
    end
  end

  def strip_attributes(text)
    text.gsub(/(<\/?(?:b|code|em|i|tt)>)/, '')
  end

end

##
# Handle text with attributes. We're a base class: there are different
# presentation classes (one, for example, uses overstrikes to handle bold and
# underlining, while another using ANSI escape sequences.

class RDoc::RI::AttributeFormatter < RDoc::RI::Formatter

  BOLD      = 1
  ITALIC    = 2
  CODE      = 4

  ATTR_MAP = {
    "b"    => BOLD,
    "code" => CODE,
    "em"   => ITALIC,
    "i"    => ITALIC,
    "tt"   => CODE
  }

  AttrChar = Struct.new :char, :attr

  class AttributeString
    attr_reader :txt

    def initialize
      @txt = []
      @optr = 0
    end

    def <<(char)
      @txt << char
    end

    def empty?
      @optr >= @txt.length
    end

    # accept non space, then all following spaces
    def next_word
      start = @optr
      len = @txt.length

      while @optr < len && @txt[@optr].char != " "
        @optr += 1
      end

      while @optr < len && @txt[@optr].char == " "
        @optr += 1
      end

      @txt[start...@optr]
    end
  end

  ##
  # Overrides base class.  Looks for <tt>...</tt> etc sequences and generates
  # an array of AttrChars.  This array is then used as the basis for the
  # split.

  def wrap(txt, prefix=@indent, linelen=@width)
    return unless txt && !txt.empty?

    txt = add_attributes_to(txt)
    next_prefix = prefix.tr("^ ", " ")
    linelen -= prefix.size

    line = []

    until txt.empty?
      word = txt.next_word
      if word.size + line.size > linelen
        write_attribute_text(prefix, line)
        prefix = next_prefix
        line = []
      end
      line.concat(word)
    end

    write_attribute_text(prefix, line) if line.length > 0
  end

  protected

  def write_attribute_text(prefix, line)
    @output.print prefix
    line.each do |achar|
      @output.print achar.char
    end
    @output.puts
  end

  def bold_print(txt)
    @output.print txt
  end

  private

  def add_attributes_to(txt)
    tokens = txt.split(%r{(</?(?:b|code|em|i|tt)>)})
    text = AttributeString.new
    attributes = 0
    tokens.each do |tok|
      case tok
      when %r{^</(\w+)>$} then attributes &= ~(ATTR_MAP[$1]||0)
      when %r{^<(\w+)>$}  then attributes  |= (ATTR_MAP[$1]||0)
      else
        tok.split(//).each {|ch| text << AttrChar.new(ch, attributes)}
      end
    end
    text
  end

end

##
# This formatter generates overstrike-style formatting, which works with
# pagers such as man and less.

class RDoc::RI::OverstrikeFormatter < RDoc::RI::AttributeFormatter

  BS = "\C-h"

  def write_attribute_text(prefix, line)
    @output.print prefix

    line.each do |achar|
      attr = achar.attr
      @output.print "_", BS if (attr & (ITALIC + CODE)) != 0
      @output.print achar.char, BS if (attr & BOLD) != 0
      @output.print achar.char
    end

    @output.puts
  end

  ##
  # Draw a string in bold

  def bold_print(text)
    text.split(//).each do |ch|
      @output.print ch, BS, ch
    end
  end

end

##
# This formatter uses ANSI escape sequences to colorize stuff works with
# pagers such as man and less.

class RDoc::RI::AnsiFormatter < RDoc::RI::AttributeFormatter

  def initialize(*args)
    super
    @output.print "\033[0m"
  end

  def write_attribute_text(prefix, line)
    @output.print prefix
    curr_attr = 0
    line.each do |achar|
      attr = achar.attr
      if achar.attr != curr_attr
        update_attributes(achar.attr)
        curr_attr = achar.attr
      end
      @output.print achar.char
    end
    update_attributes(0) unless curr_attr.zero?
    @output.puts
  end

  def bold_print(txt)
    @output.print "\033[1m#{txt}\033[m"
  end

  HEADINGS = {
    1 => ["\033[1;32m", "\033[m"],
    2 => ["\033[4;32m", "\033[m"],
    3 => ["\033[32m",   "\033[m"],
  }

  def display_heading(text, level, indent)
    level = 3 if level > 3
    heading = HEADINGS[level]
    @output.print indent
    @output.print heading[0]
    @output.print strip_attributes(text)
    @output.puts heading[1]
  end

  private

  ATTR_MAP = {
    BOLD   => "1",
    ITALIC => "33",
    CODE   => "36"
  }

  def update_attributes(attr)
    str = "\033["
    for quality in [ BOLD, ITALIC, CODE]
      unless (attr & quality).zero?
        str << ATTR_MAP[quality]
      end
    end
    @output.print str, "m"
  end

end

##
# This formatter uses HTML.

class RDoc::RI::HtmlFormatter < RDoc::RI::AttributeFormatter

  def write_attribute_text(prefix, line)
    curr_attr = 0
    line.each do |achar|
      attr = achar.attr
      if achar.attr != curr_attr
        update_attributes(curr_attr, achar.attr)
        curr_attr = achar.attr
      end
      @output.print(escape(achar.char))
    end
    update_attributes(curr_attr, 0) unless curr_attr.zero?
  end

  def draw_line(label=nil)
    if label != nil
      bold_print(label)
    end
    @output.puts("<hr>")
  end

  def bold_print(txt)
    tag("b") { txt }
  end

  def blankline()
    @output.puts("<p>")
  end

  def break_to_newline
    @output.puts("<br>")
  end

  def display_heading(text, level, indent)
    level = 4 if level > 4
    tag("h#{level}") { text }
    @output.puts
  end

  def display_list(list)
    case list.type
    when :BULLET then
      list_type = "ul"
      prefixer = proc { |ignored| "<li>" }

    when :NUMBER, :UPPERALPHA, :LOWERALPHA then
      list_type = "ol"
      prefixer = proc { |ignored| "<li>" }

    when :LABELED then
      list_type = "dl"
      prefixer = proc do |li|
        "<dt><b>" + escape(li.label) + "</b><dd>"
      end

    when :NOTE then
      list_type = "table"
      prefixer = proc do |li|
        %{<tr valign="top"><td>#{li.label.gsub(/ /, '&nbsp;')}</td><td>}
      end
    else
      fail "unknown list type"
    end

    @output.print "<#{list_type}>"
    list.contents.each do |item|
      if item.kind_of? RDoc::Markup::Flow::LI
        prefix = prefixer.call(item)
        @output.print prefix
        display_flow_item(item, prefix)
      else
        display_flow_item(item)
      end
    end
    @output.print "</#{list_type}>"
  end

  def display_verbatim_flow_item(item, prefix=@indent)
    @output.print("<pre>")
    item.body.split(/\n/).each do |line|
      @output.puts conv_html(line)
    end
    @output.puts("</pre>")
  end

  private

  ATTR_MAP = {
    BOLD   => "b>",
    ITALIC => "i>",
    CODE   => "tt>"
  }

  def update_attributes(current, wanted)
    str = ""
    # first turn off unwanted ones
    off = current & ~wanted
    for quality in [ BOLD, ITALIC, CODE]
      if (off & quality) > 0
        str << "</" + ATTR_MAP[quality]
      end
    end

    # now turn on wanted
    for quality in [ BOLD, ITALIC, CODE]
      unless (wanted & quality).zero?
        str << "<" << ATTR_MAP[quality]
      end
    end
    @output.print str
  end

  def tag(code)
    @output.print("<#{code}>")
    @output.print(yield)
    @output.print("</#{code}>")
  end

  def escape(str)
    str = str.gsub(/&/n, '&amp;')
    str.gsub!(/\"/n, '&quot;')
    str.gsub!(/>/n, '&gt;')
    str.gsub!(/</n, '&lt;')
    str
  end

end

##
# This formatter reduces extra lines for a simpler output.  It improves way
# output looks for tools like IRC bots.

class RDoc::RI::SimpleFormatter < RDoc::RI::Formatter

  ##
  # No extra blank lines

  def blankline
  end

  ##
  # Display labels only, no lines

  def draw_line(label=nil)
    unless label.nil? then
      bold_print(label)
      @output.puts
    end
  end

  ##
  # Place heading level indicators inline with heading.

  def display_heading(text, level, indent)
    text = strip_attributes(text)
    case level
    when 1
      @output.puts "= " + text.upcase
    when 2
      @output.puts "-- " + text
    else
      @output.print indent, text, "\n"
    end
  end

end

RDoc::RI::Formatter::FORMATTERS['plain']  = RDoc::RI::Formatter
RDoc::RI::Formatter::FORMATTERS['simple'] = RDoc::RI::SimpleFormatter
RDoc::RI::Formatter::FORMATTERS['bs']     = RDoc::RI::OverstrikeFormatter
RDoc::RI::Formatter::FORMATTERS['ansi']   = RDoc::RI::AnsiFormatter
RDoc::RI::Formatter::FORMATTERS['html']   = RDoc::RI::HtmlFormatter
