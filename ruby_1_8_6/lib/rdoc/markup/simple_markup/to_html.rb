require 'rdoc/markup/simple_markup/fragments'
require 'rdoc/markup/simple_markup/inline'

require 'cgi'

module SM

  class ToHtml

    LIST_TYPE_TO_HTML = {
      ListBase::BULLET =>  [ "<ul>", "</ul>" ],
      ListBase::NUMBER =>  [ "<ol>", "</ol>" ],
      ListBase::UPPERALPHA =>  [ "<ol>", "</ol>" ],
      ListBase::LOWERALPHA =>  [ "<ol>", "</ol>" ],
      ListBase::LABELED => [ "<dl>", "</dl>" ],
      ListBase::NOTE    => [ "<table>", "</table>" ],
    }

    InlineTag = Struct.new(:bit, :on, :off)

    def initialize
      init_tags
    end

    ##
    # Set up the standard mapping of attributes to HTML tags
    #
    def init_tags
      @attr_tags = [
        InlineTag.new(SM::Attribute.bitmap_for(:BOLD), "<b>", "</b>"),
        InlineTag.new(SM::Attribute.bitmap_for(:TT),   "<tt>", "</tt>"),
        InlineTag.new(SM::Attribute.bitmap_for(:EM),   "<em>", "</em>"),
      ]
    end

    ##
    # Add a new set of HTML tags for an attribute. We allow
    # separate start and end tags for flexibility
    #
    def add_tag(name, start, stop)
      @attr_tags << InlineTag.new(SM::Attribute.bitmap_for(name), start, stop)
    end

    ##
    # Given an HTML tag, decorate it with class information
    # and the like if required. This is a no-op in the base
    # class, but is overridden in HTML output classes that
    # implement style sheets

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
      @res << html_list_name(fragment.type, true) <<"\n"
      @in_list_entry.push false
    end

    def accept_list_end(am, fragment)
      if tag = @in_list_entry.pop
        @res << annotate(tag) << "\n"
      end
      @res << html_list_name(fragment.type, false) <<"\n"
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

    #######################################################################

    private

    #######################################################################

    def on_tags(res, item)
      attr_mask = item.turn_on
      return if attr_mask.zero?

      @attr_tags.each do |tag|
        if attr_mask & tag.bit != 0
          res << annotate(tag.on)
        end
      end
    end

    def off_tags(res, item)
      attr_mask = item.turn_off
      return if attr_mask.zero?

      @attr_tags.reverse_each do |tag|
        if attr_mask & tag.bit != 0
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
        when AttrChanger
          off_tags(res, item)
          on_tags(res,  item)
        when Special
          res << convert_special(item)
        else
          raise "Unknown flow element: #{item.inspect}"
        end
      end
      res
    end

    # some of these patterns are taken from SmartyPants...

    def convert_string(item)
      CGI.escapeHTML(item).
      
      
      # convert -- to em-dash, (-- to en-dash)
        gsub(/---?/, '&#8212;'). #gsub(/--/, '&#8211;').

      # convert ... to elipsis (and make sure .... becomes .<elipsis>)
        gsub(/\.\.\.\./, '.&#8230;').gsub(/\.\.\./, '&#8230;').

      # convert single closing quote
        gsub(%r{([^ \t\r\n\[\{\(])\'}) { "#$1&#8217;" }.
        gsub(%r{\'(?=\W|s\b)}) { "&#8217;" }.

      # convert single opening quote
        gsub(/'/, '&#8216;').

      # convert double closing quote
        gsub(%r{([^ \t\r\n\[\{\(])\'(?=\W)}) { "#$1&#8221;" }.

      # convert double opening quote
        gsub(/'/, '&#8220;').

      # convert copyright
        gsub(/\(c\)/, '&#169;').

      # convert and registered trademark
        gsub(/\(r\)/, '&#174;')

    end

    def convert_special(special)
      handled = false
      Attribute.each_name_of(special.type) do |name|
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
      when ListBase::BULLET, ListBase::NUMBER
        annotate("<li>")

      when ListBase::UPPERALPHA
	annotate("<li type=\"A\">")

      when ListBase::LOWERALPHA
	annotate("<li type=\"a\">")

      when ListBase::LABELED
        annotate("<dt>") +
          convert_flow(am.flow(fragment.param)) + 
          annotate("</dt>") +
          annotate("<dd>")

      when ListBase::NOTE
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
      when ListBase::BULLET, ListBase::NUMBER, ListBase::UPPERALPHA, ListBase::LOWERALPHA
        "</li>"
      when ListBase::LABELED
        "</dd>"
      when ListBase::NOTE
        "</td></tr>"
      else
        raise "Invalid list type"
      end
    end

  end

end
