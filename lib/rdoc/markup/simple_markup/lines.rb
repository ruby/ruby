##########################################################################
#
# We store the lines we're working on as objects of class Line.
# These contain the text of the line, along with a flag indicating the
# line type, and an indentation level

module SM

  class Line
    INFINITY = 9999

    BLANK     = :BLANK
    HEADING   = :HEADING
    LIST      = :LIST
    RULE      = :RULE
    PARAGRAPH = :PARAGRAPH
    VERBATIM  = :VERBATIM

    # line type
    attr_accessor :type

    # The indentation nesting level
    attr_accessor :level

    # The contents
    attr_accessor :text

    # A prefix or parameter. For LIST lines, this is
    # the text that introduced the list item (the label)
    attr_accessor  :param

    # A flag. For list lines, this is the type of the list
    attr_accessor :flag

    # the number of leading spaces
    attr_accessor :leading_spaces

    # true if this line has been deleted from the list of lines
    attr_accessor :deleted


    def initialize(text)
      @text    = text.dup
      @deleted = false

      # expand tabs
      1 while @text.gsub!(/\t+/) { ' ' * (8*$&.length - $`.length % 8)}  && $~ #`

      # Strip trailing whitespace
      @text.sub!(/\s+$/, '')

      # and look for leading whitespace
      if @text.length > 0
        @text =~ /^(\s*)/
        @leading_spaces = $1.length
      else
        @leading_spaces = INFINITY
      end
    end

    # Return true if this line is blank
    def isBlank?
      @text.length.zero?
    end

    # stamp a line with a type, a level, a prefix, and a flag
    def stamp(type, level, param="", flag=nil)
      @type, @level, @param, @flag = type, level, param, flag
    end

    ##
    # Strip off the leading margin
    #

    def strip_leading(size)
      if @text.size > size
        @text[0,size] = ""
      else
        @text = ""
      end
    end

    def to_s
      "#@type#@level: #@text"
    end
  end

  ###############################################################################
  #
  # A container for all the lines
  #

  class Lines
    include Enumerable

    attr_reader :lines   # for debugging

    def initialize(lines)
      @lines = lines
      rewind
    end

    def empty?
      @lines.size.zero?
    end

    def each
      @lines.each do |line|
        yield line unless line.deleted
      end
    end

#    def [](index)
#      @lines[index]
#    end

    def rewind
      @nextline = 0
    end

    def next
      begin
        res = @lines[@nextline]
        @nextline += 1 if @nextline < @lines.size
      end while res and res.deleted and @nextline < @lines.size
      res
    end

    def unget
      @nextline -= 1
    end

    def delete(a_line)
      a_line.deleted = true
    end

    def normalize
      margin = @lines.collect{|l| l.leading_spaces}.min
      margin = 0 if margin == Line::INFINITY
      @lines.each {|line| line.strip_leading(margin) } if margin > 0
    end

    def as_text
      @lines.map {|l| l.text}.join("\n")
    end

    def line_types
      @lines.map {|l| l.type }
    end
  end
end
