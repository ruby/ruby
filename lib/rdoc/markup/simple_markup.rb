# = Introduction
#
# SimpleMarkup parses plain text documents and attempts to decompose
# them into their constituent parts. Some of these parts are high-level:
# paragraphs, chunks of verbatim text, list entries and the like. Other
# parts happen at the character level: a piece of bold text, a word in
# code font. This markup is similar in spirit to that used on WikiWiki
# webs, where folks create web pages using a simple set of formatting
# rules.
#
# SimpleMarkup itself does no output formatting: this is left to a
# different set of classes.
#
# SimpleMarkup is extendable at runtime: you can add new markup
# elements to be recognised in the documents that SimpleMarkup parses.
#
# SimpleMarkup is intended to be the basis for a family of tools which
# share the common requirement that simple, plain-text should be
# rendered in a variety of different output formats and media. It is
# envisaged that SimpleMarkup could be the basis for formating RDoc
# style comment blocks, Wiki entries, and online FAQs.
#
# = Basic Formatting
#
# * SimpleMarkup looks for a document's natural left margin. This is
#   used as the initial margin for the document.
#
# * Consecutive lines starting at this margin are considered to be a
#   paragraph.
#
# * If a paragraph starts with a "*", "-", or with "<digit>.", then it is
#   taken to be the start of a list. The margin in increased to be the
#   first non-space following the list start flag. Subsequent lines
#   should be indented to this new margin until the list ends. For
#   example:
#
#      * this is a list with three paragraphs in
#        the first item. This is the first paragraph.
#
#        And this is the second paragraph.
#
#        1. This is an indented, numbered list.
#        2. This is the second item in that list
#
#        This is the third conventional paragraph in the
#        first list item.
#
#      * This is the second item in the original list
#
# * You can also construct labeled lists, sometimes called description
#   or definition lists. Do this by putting the label in square brackets
#   and indenting the list body:
#
#       [cat]  a small furry mammal
#              that seems to sleep a lot
#
#       [ant]  a little insect that is known
#              to enjoy picnics
#
#   A minor variation on labeled lists uses two colons to separate the
#   label from the list body:
#
#       cat::  a small furry mammal
#              that seems to sleep a lot
#
#       ant::  a little insect that is known
#              to enjoy picnics
#     
#   This latter style guarantees that the list bodies' left margins are
#   aligned: think of them as a two column table.
#
# * Any line that starts to the right of the current margin is treated
#   as verbatim text. This is useful for code listings. The example of a
#   list above is also verbatim text.
#
# * A line starting with an equals sign (=) is treated as a
#   heading. Level one headings have one equals sign, level two headings
#   have two,and so on.
#
# * A line starting with three or more hyphens (at the current indent)
#   generates a horizontal rule. THe more hyphens, the thicker the rule
#   (within reason, and if supported by the output device)
#
# * You can use markup within text (except verbatim) to change the
#   appearance of parts of that text. Out of the box, SimpleMarkup
#   supports word-based and general markup.
#
#   Word-based markup uses flag characters around individual words:
#
#   [\*word*]  displays word in a *bold* font
#   [\_word_]  displays word in an _emphasized_ font
#   [\+word+]  displays word in a +code+ font
#
#   General markup affects text between a start delimiter and and end
#   delimiter. Not surprisingly, these delimiters look like HTML markup.
#
#   [\<b>text...</b>]    displays word in a *bold* font
#   [\<em>text...</em>]  displays word in an _emphasized_ font
#   [\<i>text...</i>]    displays word in an _emphasized_ font
#   [\<tt>text...</tt>]  displays word in a +code+ font
#
#   Unlike conventional Wiki markup, general markup can cross line
#   boundaries. You can turn off the interpretation of markup by
#   preceding the first character with a backslash, so \\\<b>bold
#   text</b> and \\\*bold* produce \<b>bold text</b> and \*bold
#   respectively.
#
# = Using SimpleMarkup
#
# For information on using SimpleMarkup programatically, 
# see SM::SimpleMarkup.
#
# Author::   Dave Thomas,  dave@pragmaticprogrammer.com
# Version::  0.0
# License::  Ruby license



require 'rdoc/markup/simple_markup/fragments'
require 'rdoc/markup/simple_markup/lines.rb'

module SM  #:nodoc:

  # == Synopsis
  #
  # This code converts <tt>input_string</tt>, which is in the format
  # described in markup/simple_markup.rb, to HTML. The conversion
  # takes place in the +convert+ method, so you can use the same
  # SimpleMarkup object to convert multiple input strings.
  #
  #   require 'rdoc/markup/simple_markup'
  #   require 'rdoc/markup/simple_markup/to_html'
  #
  #   p = SM::SimpleMarkup.new
  #   h = SM::ToHtml.new
  #
  #   puts p.convert(input_string, h)
  #
  # You can extend the SimpleMarkup parser to recognise new markup
  # sequences, and to add special processing for text that matches a
  # regular epxression. Here we make WikiWords significant to the parser,
  # and also make the sequences {word} and \<no>text...</no> signify
  # strike-through text. When then subclass the HTML output class to deal
  # with these:
  #
  #   require 'rdoc/markup/simple_markup'
  #   require 'rdoc/markup/simple_markup/to_html'
  #
  #   class WikiHtml < SM::ToHtml
  #     def handle_special_WIKIWORD(special)
  #       "<font color=red>" + special.text + "</font>"
  #     end
  #   end
  #
  #   p = SM::SimpleMarkup.new
  #   p.add_word_pair("{", "}", :STRIKE)
  #   p.add_html("no", :STRIKE)
  #
  #   p.add_special(/\b([A-Z][a-z]+[A-Z]\w+)/, :WIKIWORD)
  #
  #   h = WikiHtml.new
  #   h.add_tag(:STRIKE, "<strike>", "</strike>")
  #
  #   puts "<body>" + p.convert(ARGF.read, h) + "</body>"
  #
  # == Output Formatters
  #
  # _missing_
  #
  #

  class SimpleMarkup

    SPACE = ?\s

    # List entries look like:
    #  *       text
    #  1.      text
    #  [label] text
    #  label:: text
    #
    # Flag it as a list entry, and
    # work out the indent for subsequent lines

    SIMPLE_LIST_RE = /^(
                  (  \*          (?# bullet)
                    |-           (?# bullet)
                    |\d+\.       (?# numbered )
                    |[A-Za-z]\.  (?# alphabetically numbered )
                  )
                  \s+
                )\S/x

    LABEL_LIST_RE = /^(
                        (  \[.*?\]    (?# labeled  )
                          |\S.*::     (?# note     )
                        )(?=\s|$)
                        \s*
                      )/x


    ##
    # take a block of text and use various heuristics to determine
    # it's structure (paragraphs, lists, and so on). Invoke an
    # event handler as we identify significant chunks.
    #

    def initialize
      @am = AttributeManager.new
      @output = nil
    end

    ##
    # Add to the sequences used to add formatting to an individual word 
    # (such as *bold*). Matching entries will generate attibutes
    # that the output formatters can recognize by their +name+

    def add_word_pair(start, stop, name)
      @am.add_word_pair(start, stop, name)
    end

    ##
    # Add to the sequences recognized as general markup
    #

    def add_html(tag, name)
      @am.add_html(tag, name)
    end

    ##
    # Add to other inline sequences. For example, we could add
    # WikiWords using something like:
    #
    #    parser.add_special(/\b([A-Z][a-z]+[A-Z]\w+)/, :WIKIWORD)
    #
    # Each wiki word will be presented to the output formatter 
    # via the accept_special method
    #

    def add_special(pattern, name)
      @am.add_special(pattern, name)
    end


    # We take a string, split it into lines, work out the type of
    # each line, and from there deduce groups of lines (for example
    # all lines in a paragraph). We then invoke the output formatter
    # using a Visitor to display the result

    def convert(str, op)
      @lines = Lines.new(str.split(/\r?\n/).collect { |aLine| 
                           Line.new(aLine) })
      return "" if @lines.empty?
      @lines.normalize
      assign_types_to_lines
      group = group_lines
      # call the output formatter to handle the result
      #      group.to_a.each {|i| p i}
      group.accept(@am, op)
    end


    #######
    private
    #######


    ##
    # Look through the text at line indentation. We flag each line as being
    # Blank, a paragraph, a list element, or verbatim text
    #

    def assign_types_to_lines(margin = 0, level = 0)

      while line = @lines.next
        if line.isBlank?
          line.stamp(Line::BLANK, level)
          next
        end
        
        # if a line contains non-blanks before the margin, then it must belong
        # to an outer level

        text = line.text
        
        for i in 0...margin
          if text[i] != SPACE
            @lines.unget
            return
          end
        end

        active_line = text[margin..-1]

        # Rules (horizontal lines) look like
        #
        #  ---   (three or more hyphens)
        #
        # The more hyphens, the thicker the rule
        #

        if /^(---+)\s*$/ =~ active_line
          line.stamp(Line::RULE, level, $1.length-2)
          next
        end

        # Then look for list entries. First the ones that have to have
        # text following them (* xxx, - xxx, and dd. xxx)

        if SIMPLE_LIST_RE =~ active_line

          offset = margin + $1.length
          prefix = $2
          prefix_length = prefix.length

          flag = case prefix
                 when "*","-" then ListBase::BULLET
                 when /^\d/   then ListBase::NUMBER
                 when /^[A-Z]/ then ListBase::UPPERALPHA
                 when /^[a-z]/ then ListBase::LOWERALPHA
                 else raise "Invalid List Type: #{self.inspect}"
                 end

          line.stamp(Line::LIST, level+1, prefix, flag)
          text[margin, prefix_length] = " " * prefix_length
          assign_types_to_lines(offset, level + 1)
          next
        end


        if LABEL_LIST_RE =~ active_line
          offset = margin + $1.length
          prefix = $2
          prefix_length = prefix.length

          next if handled_labeled_list(line, level, margin, offset, prefix)
        end

        # Headings look like
        # = Main heading
        # == Second level
        # === Third
        #
        # Headings reset the level to 0

        if active_line[0] == ?= and active_line =~ /^(=+)\s*(.*)/
          prefix_length = $1.length
          prefix_length = 6 if prefix_length > 6
          line.stamp(Line::HEADING, 0, prefix_length)
          line.strip_leading(margin + prefix_length)
          next
        end
        
        # If the character's a space, then we have verbatim text,
        # otherwise 

        if active_line[0] == SPACE
          line.strip_leading(margin) if margin > 0
          line.stamp(Line::VERBATIM, level)
        else
          line.stamp(Line::PARAGRAPH, level)
        end
      end
    end

    # Handle labeled list entries, We have a special case
    # to deal with. Because the labels can be long, they force
    # the remaining block of text over the to right:
    #
    # this is a long label that I wrote:: and here is the
    #                                     block of text with
    #                                     a silly margin
    #
    # So we allow the special case. If the label is followed
    # by nothing, and if the following line is indented, then
    # we take the indent of that line as the new margin
    #
    # this is a long label that I wrote::
    #     here is a more reasonably indented block which
    #     will ab attached to the label.
    #
    
    def handled_labeled_list(line, level, margin, offset, prefix)
      prefix_length = prefix.length
      text = line.text
      flag = nil
      case prefix
      when /^\[/
        flag = ListBase::LABELED
        prefix = prefix[1, prefix.length-2]
      when /:$/
        flag = ListBase::NOTE
        prefix.chop!
      else raise "Invalid List Type: #{self.inspect}"
      end
      
      # body is on the next line
      
      if text.length <= offset
        original_line = line
        line = @lines.next
        return(false) unless line
        text = line.text
        
        for i in 0..margin
          if text[i] != SPACE
            @lines.unget
            return false
          end
        end
        i = margin
        i += 1 while text[i] == SPACE
        if i >= text.length
          @lines.unget
          return false
        else
          offset = i
          prefix_length = 0
          @lines.delete(original_line)
        end
      end
      
      line.stamp(Line::LIST, level+1, prefix, flag)
      text[margin, prefix_length] = " " * prefix_length
      assign_types_to_lines(offset, level + 1)
      return true
    end

    # Return a block consisting of fragments which are
    # paragraphs, list entries or verbatim text. We merge consecutive
    # lines of the same type and level together. We are also slightly
    # tricky with lists: the lines following a list introduction
    # look like paragraph lines at the next level, and we remap them
    # into list entries instead

    def group_lines
      @lines.rewind

      inList = false
      wantedType = wantedLevel = nil

      block = LineCollection.new
      group = nil

      while line = @lines.next
        if line.level == wantedLevel and line.type == wantedType
          group.add_text(line.text)
        else
          group = block.fragment_for(line)
          block.add(group)
          if line.type == Line::LIST
            wantedType = Line::PARAGRAPH
          else
            wantedType = line.type
          end
          wantedLevel = line.type == Line::HEADING ? line.param : line.level
        end
      end

      block.normalize
      block
    end

    ## for debugging, we allow access to our line contents as text
    def content
      @lines.as_text
    end
    public :content

    ## for debugging, return the list of line types
    def get_line_types
      @lines.line_types
    end
    public :get_line_types
  end

end
