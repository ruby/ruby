module RI
  class RiFormatter

    attr_reader :indent
    
    def initialize(width, indent)
      @width = width
      @indent = indent
    end
    
    
    ######################################################################
    
    def draw_line(label=nil)
      len = @width
      len -= (label.size+1) if label
      print "-"*len
      print(" ", label) if label
      puts
    end
    
    ######################################################################
    
    def wrap(txt,  prefix=@indent, linelen=@width)
      return unless txt && !txt.empty?
      work = txt.dup
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
      puts (prefix +  res.join("\n" + next_prefix))
    end

    ######################################################################

    def blankline
      puts
    end
    
    ######################################################################

    # convert HTML entities back to ASCII
    def conv_html(txt)
      txt.
          gsub(%r{<tt>(.*?)</tt>}) { "+#$1+" } .
          gsub(%r{<b>(.*?)</b>}) { "*#$1*" } .
          gsub(%r{<em>(.*?)</em>}) { "_#$1_" } .
          gsub(/&gt;/, '>').
          gsub(/&lt;/, '<').
          gsub(/&quot;/, '"').
          gsub(/&amp;/, '&')
          
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
        item.body.split(/\n/).each do |line|
          print @indent, conv_html(line), "\n"
        end
        blankline

      when SM::Flow::H
        text = conv_html(item.text.join)
        case item.level
        when 1
          ul = "=" * text.length
          puts
          puts text.upcase
          puts ul
          puts

        when 2
          ul = "-" * text.length
          puts
          puts text
          puts ul
          puts
        else
          print "\n", @indent, text, "\n\n"
        end
      else
        fail "Unknown flow element: #{item.class}"
      end
    end

    ######################################################################

    def display_flow(flow)
      flow.each do |f|
        display_flow_item(f)
      end
    end
  end
end
