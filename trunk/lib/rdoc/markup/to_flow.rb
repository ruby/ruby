require 'rdoc/markup/formatter'
require 'rdoc/markup/fragments'
require 'rdoc/markup/inline'
require 'cgi'

class RDoc::Markup

  module Flow
    P = Struct.new(:body)
    VERB = Struct.new(:body)
    RULE = Struct.new(:width)
    class LIST
      attr_reader :type, :contents
      def initialize(type)
        @type = type
        @contents = []
      end
      def <<(stuff)
        @contents << stuff
      end
    end
    LI = Struct.new(:label, :body)
    H = Struct.new(:level, :text)
  end

  class ToFlow < RDoc::Markup::Formatter
    LIST_TYPE_TO_HTML = {
      :BULLET     =>  [ "<ul>", "</ul>" ],
      :NUMBER     =>  [ "<ol>", "</ol>" ],
      :UPPERALPHA =>  [ "<ol>", "</ol>" ],
      :LOWERALPHA =>  [ "<ol>", "</ol>" ],
      :LABELED    =>  [ "<dl>", "</dl>" ],
      :NOTE       =>  [ "<table>", "</table>" ],
    }

    InlineTag = Struct.new(:bit, :on, :off)

    def initialize
      super

      init_tags
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
    # end tags for flexibility

    def add_tag(name, start, stop)
      @attr_tags << InlineTag.new(RDoc::Markup::Attribute.bitmap_for(name), start, stop)
    end

    ##
    # Given an HTML tag, decorate it with class information and the like if
    # required. This is a no-op in the base class, but is overridden in HTML
    # output classes that implement style sheets

    def annotate(tag)
      tag
    end

    ##
    # Here's the client side of the visitor pattern

    def start_accepting
      @res = []
      @list_stack = []
    end

    def end_accepting
      @res
    end

    def accept_paragraph(am, fragment)
      @res << Flow::P.new((convert_flow(am.flow(fragment.txt))))
    end

    def accept_verbatim(am, fragment)
      @res << Flow::VERB.new((convert_flow(am.flow(fragment.txt))))
    end

    def accept_rule(am, fragment)
      size = fragment.param
      size = 10 if size > 10
      @res << Flow::RULE.new(size)
    end

    def accept_list_start(am, fragment)
      @list_stack.push(@res)
      list = Flow::LIST.new(fragment.type)
      @res << list
      @res = list
    end

    def accept_list_end(am, fragment)
      @res = @list_stack.pop
    end

    def accept_list_item(am, fragment)
      @res << Flow::LI.new(fragment.param, convert_flow(am.flow(fragment.txt)))
    end

    def accept_blank_line(am, fragment)
      # @res << annotate("<p />") << "\n"
    end

    def accept_heading(am, fragment)
      @res << Flow::H.new(fragment.head_level, convert_flow(am.flow(fragment.txt)))
    end

    private

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

    def convert_string(item)
      CGI.escapeHTML(item)
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

  end

end

