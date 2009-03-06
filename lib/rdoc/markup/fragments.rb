require 'rdoc/markup'
require 'rdoc/markup/lines'

class RDoc::Markup

  ##
  # A Fragment is a chunk of text, subclassed as a paragraph, a list
  # entry, or verbatim text.

  class Fragment
    attr_reader   :level, :param, :txt
    attr_accessor :type

    ##
    # This is a simple factory system that lets us associate fragement
    # types (a string) with a subclass of fragment

    TYPE_MAP = {}

    def self.type_name(name)
      TYPE_MAP[name] = self
    end

    def self.for(line)
      klass =  TYPE_MAP[line.type] ||
        raise("Unknown line type: '#{line.type.inspect}:' '#{line.text}'")
      return klass.new(line.level, line.param, line.flag, line.text)
    end

    def initialize(level, param, type, txt)
      @level = level
      @param = param
      @type  = type
      @txt   = ""
      add_text(txt) if txt
    end

    def add_text(txt)
      @txt << " " if @txt.length > 0
      @txt << txt.tr_s("\n ", "  ").strip
    end

    def to_s
      "L#@level: #{self.class.name.split('::')[-1]}\n#@txt"
    end

  end

  ##
  # A paragraph is a fragment which gets wrapped to fit. We remove all
  # newlines when we're created, and have them put back on output.

  class Paragraph < Fragment
    type_name :PARAGRAPH
  end

  class BlankLine < Paragraph
    type_name :BLANK
  end

  class Heading < Paragraph
    type_name :HEADING

    def head_level
      @param.to_i
    end
  end

  ##
  # A List is a fragment with some kind of label

  class ListBase < Paragraph
    LIST_TYPES = [
      :BULLET,
      :NUMBER,
      :UPPERALPHA,
      :LOWERALPHA,
      :LABELED,
      :NOTE,
    ]
  end

  class ListItem < ListBase
    type_name :LIST

    def to_s
      text = if [:NOTE, :LABELED].include? type then
               "#{@param}: #{@txt}"
             else
               @txt
             end

      "L#@level: #{type} #{self.class.name.split('::')[-1]}\n#{text}"
    end

  end

  class ListStart < ListBase
    def initialize(level, param, type)
      super(level, param, type, nil)
    end
  end

  class ListEnd < ListBase
    def initialize(level, type)
      super(level, "", type, nil)
    end
  end

  ##
  # Verbatim code contains lines that don't get wrapped.

  class Verbatim < Fragment
    type_name  :VERBATIM

    def add_text(txt)
      @txt << txt.chomp << "\n"
    end

  end

  ##
  # A horizontal rule

  class Rule < Fragment
    type_name :RULE
  end

  ##
  # Collect groups of lines together. Each group will end up containing a flow
  # of text.

  class LineCollection

    def initialize
      @fragments = []
    end

    def add(fragment)
      @fragments << fragment
    end

    def each(&b)
      @fragments.each(&b)
    end

    def to_a # :nodoc:
      @fragments.map {|fragment| fragment.to_s}
    end

    ##
    # Factory for different fragment types

    def fragment_for(*args)
      Fragment.for(*args)
    end

    ##
    # Tidy up at the end

    def normalize
      change_verbatim_blank_lines
      add_list_start_and_ends
      add_list_breaks
      tidy_blank_lines
    end

    def to_s
      @fragments.join("\n----\n")
    end

    def accept(am, visitor)
      visitor.start_accepting

      @fragments.each do |fragment|
        case fragment
        when Verbatim
          visitor.accept_verbatim(am, fragment)
        when Rule
          visitor.accept_rule(am, fragment)
        when ListStart
          visitor.accept_list_start(am, fragment)
        when ListEnd
          visitor.accept_list_end(am, fragment)
        when ListItem
          visitor.accept_list_item(am, fragment)
        when BlankLine
          visitor.accept_blank_line(am, fragment)
        when Heading
          visitor.accept_heading(am, fragment)
        when Paragraph
          visitor.accept_paragraph(am, fragment)
        end
      end

      visitor.end_accepting
    end

    private

    # If you have:
    #
    #    normal paragraph text.
    #
    #       this is code
    #
    #       and more code
    #
    # You'll end up with the fragments Paragraph, BlankLine, Verbatim,
    # BlankLine, Verbatim, BlankLine, etc.
    #
    # The BlankLine in the middle of the verbatim chunk needs to be changed to
    # a real verbatim newline, and the two verbatim blocks merged

    def change_verbatim_blank_lines
      frag_block = nil
      blank_count = 0
      @fragments.each_with_index do |frag, i|
        if frag_block.nil?
          frag_block = frag if Verbatim === frag
        else
          case frag
          when Verbatim
            blank_count.times { frag_block.add_text("\n") }
            blank_count = 0
            frag_block.add_text(frag.txt)
            @fragments[i] = nil    # remove out current fragment
          when BlankLine
            if frag_block
              blank_count += 1
              @fragments[i] = nil
            end
          else
            frag_block = nil
            blank_count = 0
          end
        end
      end
      @fragments.compact!
    end

    ##
    # List nesting is implicit given the level of indentation. Make it
    # explicit, just to make life a tad easier for the output processors

    def add_list_start_and_ends
      level = 0
      res = []
      type_stack = []

      @fragments.each do |fragment|
        # $stderr.puts "#{level} : #{fragment.class.name} : #{fragment.level}"
        new_level = fragment.level
        while (level < new_level)
          level += 1
          type = fragment.type
          res << ListStart.new(level, fragment.param, type) if type
          type_stack.push type
          # $stderr.puts "Start: #{level}"
        end

        while level > new_level
          type = type_stack.pop
          res << ListEnd.new(level, type) if type
          level -= 1
          # $stderr.puts "End: #{level}, #{type}"
        end

        res << fragment
        level = fragment.level
      end
      level.downto(1) do |i|
        type = type_stack.pop
        res << ListEnd.new(i, type) if type
      end

      @fragments = res
    end

    ##
    # Inserts start/ends between list entries at the same level that have
    # different element types

    def add_list_breaks
      res = @fragments

      @fragments = []
      list_stack = []

      res.each do |fragment|
        case fragment
        when ListStart
          list_stack.push fragment
        when ListEnd
          start = list_stack.pop
          fragment.type = start.type
        when ListItem
          l = list_stack.last
          if fragment.type != l.type
            @fragments << ListEnd.new(l.level, l.type)
            start = ListStart.new(l.level, fragment.param, fragment.type)
            @fragments << start
            list_stack.pop
            list_stack.push start
          end
        else
          ;
        end
        @fragments << fragment
      end
    end

    ##
    # Tidy up the blank lines:
    # * change Blank/ListEnd into ListEnd/Blank
    # * remove blank lines at the front

    def tidy_blank_lines
      (@fragments.size - 1).times do |i|
        if BlankLine === @fragments[i] and ListEnd === @fragments[i+1] then
          @fragments[i], @fragments[i+1] = @fragments[i+1], @fragments[i]
        end
      end

      # remove leading blanks
      @fragments.each_with_index do |f, i|
        break unless f.kind_of? BlankLine
        @fragments[i] = nil
      end

      @fragments.compact!
    end

  end

end

