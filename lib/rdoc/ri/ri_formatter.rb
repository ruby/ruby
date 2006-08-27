module RI
  class TextFormatter

    attr_reader :indent
    
    def initialize(options, indent)
      @options = options
      @width   = options.width
      @indent  = indent
    end
    
    
    ######################################################################
    
    def draw_line(label=nil)
      len = @width
      len -= (label.size+1) if label
      print "-"*len
      if label
        print(" ")
        bold_print(label) 
      end
      puts
    end
    
    ######################################################################
    
    def wrap(txt,  prefix=@indent, linelen=@width)
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
      puts(prefix + res.join("\n" + next_prefix))
    end

    ######################################################################

    def blankline
      puts
    end
    
    ######################################################################

    # called when we want to ensure a nbew 'wrap' starts on a newline
    # Only needed for HtmlFormatter, because the rest do their
    # own line breaking

    def break_to_newline
    end
    
    ######################################################################

    def bold_print(txt)
      print txt
    end

    ######################################################################

    def raw_print_line(txt)
      puts txt
    end

    ######################################################################

    # convert HTML entities back to ASCII
    def conv_html(txt)
      txt.
          gsub(/&gt;/, '>').
          gsub(/&lt;/, '<').
          gsub(/&quot;/, '"').
          gsub(/&amp;/, '&')
          
    end

    # convert markup into display form
    def conv_markup(txt)
      txt.
          gsub(%r{<tt>(.*?)</tt>}) { "+#$1+" } .
          gsub(%r{<code>(.*?)</code>}) { "+#$1+" } .
          gsub(%r{<b>(.*?)</b>}) { "*#$1*" } .
          gsub(%r{<em>(.*?)</em>}) { "_#$1_" }
    end

    ######################################################################

    def display_list(list)
      case list.type

      when SM::ListBase::BULLET 
        prefixer = proc { |ignored| @indent + "*   " }

      when SM::ListBase::NUMBER,
      SM::ListBase::UPPERALPHA,
      SM::ListBase::LOWERALPHA

        start = case list.type
                when SM::ListBase::NUMBER      then 1
                when  SM::ListBase::UPPERALPHA then 'A'
                when SM::ListBase::LOWERALPHA  then 'a'
                end
        prefixer = proc do |ignored|
          res = @indent + "#{start}.".ljust(4)
          start = start.succ
          res
        end
        
      when SM::ListBase::LABELED
        prefixer = proc do |li|
          li.label
        end

      when SM::ListBase::NOTE
        longest = 0
        list.contents.each do |item|
          if item.kind_of?(SM::Flow::LI) && item.label.length > longest
            longest = item.label.length
          end
        end

        prefixer = proc do |li|
          @indent + li.label.ljust(longest+1)
        end

      else
        fail "unknown list type"

      end

      list.contents.each do |item|
        if item.kind_of? SM::Flow::LI
          prefix = prefixer.call(item)
          display_flow_item(item, prefix)
        else
          display_flow_item(item)
        end
       end
    end

    ######################################################################

    def display_flow_item(item, prefix=@indent)
      case item
      when SM::Flow::P, SM::Flow::LI
        wrap(conv_html(item.body), prefix)
        blankline
        
      when SM::Flow::LIST
        display_list(item)

      when SM::Flow::VERB
        display_verbatim_flow_item(item, @indent)

      when SM::Flow::H
        display_heading(conv_html(item.text), item.level, @indent)

      when SM::Flow::RULE
        draw_line

      else
        fail "Unknown flow element: #{item.class}"
      end
    end

    ######################################################################

    def display_verbatim_flow_item(item, prefix=@indent)
        item.body.split(/\n/).each do |line|
          print @indent, conv_html(line), "\n"
        end
        blankline
    end

    ######################################################################

    def display_heading(text, level, indent)
      text = strip_attributes(text)
      case level
      when 1
        ul = "=" * text.length
        puts
        puts text.upcase
        puts ul
#        puts
        
      when 2
        ul = "-" * text.length
        puts
        puts text
        puts ul
#        puts
      else
        print indent, text, "\n"
      end
    end


    def display_flow(flow)
      flow.each do |f|
        display_flow_item(f)
      end
    end

    def strip_attributes(txt)
      tokens = txt.split(%r{(</?(?:b|code|em|i|tt)>)})
      text = [] 
      attributes = 0
      tokens.each do |tok|
        case tok
        when %r{^</(\w+)>$}, %r{^<(\w+)>$}
          ;
        else
          text << tok
        end
      end
      text.join
    end


  end
  
  
  ######################################################################
  # Handle text with attributes. We're a base class: there are
  # different presentation classes (one, for example, uses overstrikes
  # to handle bold and underlining, while another using ANSI escape
  # sequences
  
  class AttributeFormatter < TextFormatter
    
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

    # TODO: struct?
    class AttrChar
      attr_reader :char
      attr_reader :attr

      def initialize(char, attr)
        @char = char
        @attr = attr
      end
    end

    
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

    ######################################################################
    # overrides base class. Looks for <tt>...</tt> etc sequences
    # and generates an array of AttrChars. This array is then used
    # as the basis for the split

    def wrap(txt,  prefix=@indent, linelen=@width)
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

    # overridden in specific formatters

    def write_attribute_text(prefix, line)
      print prefix
      line.each do |achar|
        print achar.char
      end
      puts
    end

    # again, overridden

    def bold_print(txt)
      print txt
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


  ##################################################
  
  # This formatter generates overstrike-style formatting, which
  # works with pagers such as man and less.

  class OverstrikeFormatter < AttributeFormatter

    BS = "\C-h"

    def write_attribute_text(prefix, line)
      print prefix
      line.each do |achar|
        attr = achar.attr
        if (attr & (ITALIC+CODE)) != 0
          print "_", BS
        end
        if (attr & BOLD) != 0
          print achar.char, BS
        end
        print achar.char
      end
      puts
    end

    # draw a string in bold
    def bold_print(text)
      text.split(//).each do |ch|
        print ch, BS, ch
      end
    end
  end

  ##################################################
  
  # This formatter uses ANSI escape sequences
  # to colorize stuff
  # works with pages such as man and less.

  class AnsiFormatter < AttributeFormatter

    def initialize(*args)
      print "\033[0m"
      super
    end

    def write_attribute_text(prefix, line)
      print prefix
      curr_attr = 0
      line.each do |achar|
        attr = achar.attr
        if achar.attr != curr_attr
          update_attributes(achar.attr)
          curr_attr = achar.attr
        end
        print achar.char
      end
      update_attributes(0) unless curr_attr.zero?
      puts
    end


    def bold_print(txt)
      print "\033[1m#{txt}\033[m"
    end

    HEADINGS = {
      1 => [ "\033[1;32m", "\033[m" ] ,
      2 => ["\033[4;32m", "\033[m" ],
      3 => ["\033[32m", "\033[m" ]
    }

    def display_heading(text, level, indent)
      level = 3 if level > 3
      heading = HEADINGS[level]
      print indent
      print heading[0]
      print strip_attributes(text)
      puts heading[1]
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
      print str, "m"
    end
  end

  ##################################################
  
  # This formatter uses HTML.

  class HtmlFormatter < AttributeFormatter

    def initialize(*args)
      super
    end

    def write_attribute_text(prefix, line)
      curr_attr = 0
      line.each do |achar|
        attr = achar.attr
        if achar.attr != curr_attr
          update_attributes(curr_attr, achar.attr)
          curr_attr = achar.attr
        end
        print(escape(achar.char))
      end
      update_attributes(curr_attr, 0) unless curr_attr.zero?
    end

    def draw_line(label=nil)
      if label != nil
        bold_print(label)
      end
      puts("<hr>")
    end

    def bold_print(txt)
      tag("b") { txt }
    end

    def blankline()
      puts("<p>")
    end

    def break_to_newline
      puts("<br>")
    end

    def display_heading(text, level, indent)
      level = 4 if level > 4
      tag("h#{level}") { text }
      puts
    end
    
    ######################################################################

    def display_list(list)

      case list.type
      when SM::ListBase::BULLET 
        list_type = "ul"
        prefixer = proc { |ignored| "<li>" }

      when SM::ListBase::NUMBER,
      SM::ListBase::UPPERALPHA,
      SM::ListBase::LOWERALPHA
        list_type = "ol"
        prefixer = proc { |ignored| "<li>" }
        
      when SM::ListBase::LABELED
        list_type = "dl"
        prefixer = proc do |li|
          "<dt><b>" + escape(li.label) + "</b><dd>"
        end

      when SM::ListBase::NOTE
        list_type = "table"
        prefixer = proc do |li|
          %{<tr valign="top"><td>#{li.label.gsub(/ /, '&nbsp;')}</td><td>}
        end
      else
        fail "unknown list type"
      end

      print "<#{list_type}>"
      list.contents.each do |item|
        if item.kind_of? SM::Flow::LI
          prefix = prefixer.call(item)
          print prefix
          display_flow_item(item, prefix)
        else
          display_flow_item(item)
        end
      end
      print "</#{list_type}>"
    end

    def display_verbatim_flow_item(item, prefix=@indent)
        print("<pre>")
        puts item.body
        puts("</pre>")
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
      print str
    end

    def tag(code)
        print("<#{code}>")
        print(yield)
        print("</#{code}>")
    end

    def escape(str)
      str.
          gsub(/&/n, '&amp;').
          gsub(/\"/n, '&quot;').
          gsub(/>/n, '&gt;').
          gsub(/</n, '&lt;')
    end

  end

  ##################################################
  
  # This formatter reduces extra lines for a simpler output.
  # It improves way output looks for tools like IRC bots.

  class SimpleFormatter < TextFormatter

    ######################################################################

    # No extra blank lines

    def blankline
    end

    ######################################################################

    # Display labels only, no lines

    def draw_line(label=nil)
      unless label.nil? then
        bold_print(label) 
        puts
      end
    end

    ######################################################################

    # Place heading level indicators inline with heading.

    def display_heading(text, level, indent)
      text = strip_attributes(text)
      case level
      when 1
        puts "= " + text.upcase
      when 2
        puts "-- " + text
      else
        print indent, text, "\n"
      end
    end

  end


  # Finally, fill in the list of known formatters

  class TextFormatter

    FORMATTERS = {
      "ansi"   => AnsiFormatter,
      "bs"     => OverstrikeFormatter,
      "html"   => HtmlFormatter,
      "plain"  => TextFormatter,
      "simple" => SimpleFormatter,
    }
      
    def TextFormatter.list
      FORMATTERS.keys.sort.join(", ")
    end

    def TextFormatter.for(name)
      FORMATTERS[name.downcase]
    end

  end

end


