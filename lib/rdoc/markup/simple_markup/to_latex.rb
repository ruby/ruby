require 'rdoc/markup/simple_markup/fragments'
require 'rdoc/markup/simple_markup/inline'

require 'cgi'

module SM

  # Convert SimpleMarkup to basic LaTeX report format

  class ToLaTeX

    BS = "\020"   # \
    OB = "\021"   # {
    CB = "\022"   # }
    DL = "\023"   # Dollar

    BACKSLASH   = "#{BS}symbol#{OB}92#{CB}"
    HAT         = "#{BS}symbol#{OB}94#{CB}"
    BACKQUOTE   = "#{BS}symbol#{OB}0#{CB}"
    TILDE       = "#{DL}#{BS}sim#{DL}"
    LESSTHAN    = "#{DL}<#{DL}"
    GREATERTHAN = "#{DL}>#{DL}"

    def self.l(str)
      str.tr('\\', BS).tr('{', OB).tr('}', CB).tr('$', DL)
    end

    def l(arg)
      SM::ToLaTeX.l(arg)
    end

    LIST_TYPE_TO_LATEX = {
      ListBase::BULLET =>  [ l("\\begin{itemize}"), l("\\end{itemize}") ],
      ListBase::NUMBER =>  [ l("\\begin{enumerate}"), l("\\end{enumerate}"), "\\arabic" ],
      ListBase::UPPERALPHA =>  [ l("\\begin{enumerate}"), l("\\end{enumerate}"), "\\Alph" ],
      ListBase::LOWERALPHA =>  [ l("\\begin{enumerate}"), l("\\end{enumerate}"), "\\alph" ],
      ListBase::LABELED => [ l("\\begin{description}"), l("\\end{description}") ],
      ListBase::NOTE    => [
        l("\\begin{tabularx}{\\linewidth}{@{} l X @{}}"), 
        l("\\end{tabularx}") ],
    }

    InlineTag = Struct.new(:bit, :on, :off)

    def initialize
      init_tags
      @list_depth = 0
      @prev_list_types = []
    end

    ##
    # Set up the standard mapping of attributes to LaTeX
    #
    def init_tags
      @attr_tags = [
        InlineTag.new(SM::Attribute.bitmap_for(:BOLD), l("\\textbf{"), l("}")),
        InlineTag.new(SM::Attribute.bitmap_for(:TT),   l("\\texttt{"), l("}")),
        InlineTag.new(SM::Attribute.bitmap_for(:EM),   l("\\emph{"), l("}")),
      ]
    end

    ##
    # Escape a LaTeX string
    def escape(str)
# $stderr.print "FE: ", str
      s = str.
#        sub(/\s+$/, '').
        gsub(/([_\${}&%#])/, "#{BS}\\1").
        gsub(/\\/, BACKSLASH).
        gsub(/\^/, HAT).
        gsub(/~/,  TILDE).
        gsub(/</,  LESSTHAN).
        gsub(/>/,  GREATERTHAN).
        gsub(/,,/, ",{},").
        gsub(/\`/,  BACKQUOTE)
# $stderr.print "-> ", s, "\n"
      s
    end

    ##
    # Add a new set of LaTeX tags for an attribute. We allow
    # separate start and end tags for flexibility
    #
    def add_tag(name, start, stop)
      @attr_tags << InlineTag.new(SM::Attribute.bitmap_for(name), start, stop)
    end


    ## 
    # Here's the client side of the visitor pattern

    def start_accepting
      @res = ""
      @in_list_entry = []
    end

    def end_accepting
      @res.tr(BS, '\\').tr(OB, '{').tr(CB, '}').tr(DL, '$')
    end

    def accept_paragraph(am, fragment)
      @res << wrap(convert_flow(am.flow(fragment.txt)))
      @res << "\n"
    end

    def accept_verbatim(am, fragment)
      @res << "\n\\begin{code}\n"
      @res << fragment.txt.sub(/[\n\s]+\Z/, '')
      @res << "\n\\end{code}\n\n"
    end

    def accept_rule(am, fragment)
      size = fragment.param
      size = 10 if size > 10
      @res << "\n\n\\rule{\\linewidth}{#{size}pt}\n\n"
    end

    def accept_list_start(am, fragment)
      @res << list_name(fragment.type, true) <<"\n"
      @in_list_entry.push false
    end

    def accept_list_end(am, fragment)
      if tag = @in_list_entry.pop
        @res << tag << "\n"
      end
      @res << list_name(fragment.type, false) <<"\n"
    end

    def accept_list_item(am, fragment)
      if tag = @in_list_entry.last
        @res << tag << "\n"
      end
      @res << list_item_start(am, fragment)
      @res << wrap(convert_flow(am.flow(fragment.txt))) << "\n"
      @in_list_entry[-1] = list_end_for(fragment.type)
    end

    def accept_blank_line(am, fragment)
      # @res << "\n"
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
          res << tag.on
        end
      end
    end

    def off_tags(res, item)
      attr_mask = item.turn_off
      return if attr_mask.zero?

      @attr_tags.reverse_each do |tag|
        if attr_mask & tag.bit != 0
          res << tag.off
        end
      end
    end

    def convert_flow(flow)
      res = ""
      flow.each do |item|
        case item
        when String
#          $stderr.puts "Converting '#{item}'"
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

      escape(item).
      
      
      # convert ... to elipsis (and make sure .... becomes .<elipsis>)
        gsub(/\.\.\.\./, '.\ldots{}').gsub(/\.\.\./, '\ldots{}').

      # convert single closing quote
        gsub(%r{([^ \t\r\n\[\{\(])\'}) { "#$1'" }.
        gsub(%r{\'(?=\W|s\b)}) { "'" }.

      # convert single opening quote
        gsub(/'/, '`').

      # convert double closing quote
        gsub(%r{([^ \t\r\n\[\{\(])\"(?=\W)}) { "#$1''" }.

      # convert double opening quote
        gsub(/"/, "``").

      # convert copyright
        gsub(/\(c\)/, '\copyright{}')

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
        case level
        when 1 then "\\chapter{"
        when 2 then "\\section{"
        when 3 then "\\subsection{"
        when 4 then "\\subsubsection{"
        else  "\\paragraph{"
        end +
        convert_flow(flow) + 
        "}\n"
    end

    def list_name(list_type, is_open_tag)
      tags = LIST_TYPE_TO_LATEX[list_type] || raise("Invalid list type: #{list_type.inspect}")
      if tags[2] # enumerate
        if is_open_tag
          @list_depth += 1
          if @prev_list_types[@list_depth] != tags[2]
            case @list_depth
            when 1
              roman = "i"
            when 2
              roman = "ii"
            when 3
              roman = "iii"
            when 4
              roman = "iv"
            else
              raise("Too deep list: level #{@list_depth}")
            end
            @prev_list_types[@list_depth] = tags[2]
            return l("\\renewcommand{\\labelenum#{roman}}{#{tags[2]}{enum#{roman}}}") + "\n" + tags[0]
          end
        else
          @list_depth -= 1
        end
      end
      tags[ is_open_tag ? 0 : 1]
    end

    def list_item_start(am, fragment)
      case fragment.type
      when ListBase::BULLET, ListBase::NUMBER, ListBase::UPPERALPHA, ListBase::LOWERALPHA
        "\\item "

      when ListBase::LABELED
        "\\item[" + convert_flow(am.flow(fragment.param)) + "] "

      when ListBase::NOTE
          convert_flow(am.flow(fragment.param)) + " & "
      else
        raise "Invalid list type"
      end
    end

    def list_end_for(fragment_type)
      case fragment_type
      when ListBase::BULLET, ListBase::NUMBER, ListBase::UPPERALPHA, ListBase::LOWERALPHA, ListBase::LABELED
        ""
      when ListBase::NOTE
        "\\\\\n"
      else
        raise "Invalid list type"
      end
    end

  end

end
