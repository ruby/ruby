require 'rdoc'

##
# RDoc::Markup parses plain text documents and attempts to decompose them into
# their constituent parts.  Some of these parts are high-level: paragraphs,
# chunks of verbatim text, list entries and the like.  Other parts happen at
# the character level: a piece of bold text, a word in code font.  This markup
# is similar in spirit to that used on WikiWiki webs, where folks create web
# pages using a simple set of formatting rules.
#
# RDoc::Markup itself does no output formatting: this is left to a different
# set of classes.
#
# RDoc::Markup is extendable at runtime: you can add \new markup elements to
# be recognised in the documents that RDoc::Markup parses.
#
# RDoc::Markup is intended to be the basis for a family of tools which share
# the common requirement that simple, plain-text should be rendered in a
# variety of different output formats and media.  It is envisaged that
# RDoc::Markup could be the basis for formatting RDoc style comment blocks,
# Wiki entries, and online FAQs.
#
# == Synopsis
#
# This code converts +input_string+ to HTML.  The conversion takes place in
# the +convert+ method, so you can use the same RDoc::Markup converter to
# convert multiple input strings.
#
#   require 'rdoc/markup/to_html'
#
#   h = RDoc::Markup::ToHtml.new
#
#   puts h.convert(input_string)
#
# You can extend the RDoc::Markup parser to recognise new markup
# sequences, and to add special processing for text that matches a
# regular expression.  Here we make WikiWords significant to the parser,
# and also make the sequences {word} and \<no>text...</no> signify
# strike-through text.  When then subclass the HTML output class to deal
# with these:
#
#   require 'rdoc/markup'
#   require 'rdoc/markup/to_html'
#
#   class WikiHtml < RDoc::Markup::ToHtml
#     def handle_special_WIKIWORD(special)
#       "<font color=red>" + special.text + "</font>"
#     end
#   end
#
#   m = RDoc::Markup.new
#   m.add_word_pair("{", "}", :STRIKE)
#   m.add_html("no", :STRIKE)
#
#   m.add_special(/\b([A-Z][a-z]+[A-Z]\w+)/, :WIKIWORD)
#
#   wh = WikiHtml.new
#   wh.add_tag(:STRIKE, "<strike>", "</strike>")
#
#   puts "<body>#{wh.convert ARGF.read}</body>"
#
#--
# Author::   Dave Thomas,  dave@pragmaticprogrammer.com
# License::  Ruby license

class RDoc::Markup

  SPACE = ?\s

  # List entries look like:
  #   *       text
  #   1.      text
  #   [label] text
  #   label:: text
  #
  # Flag it as a list entry, and work out the indent for subsequent lines

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
                      )(?:\s+|$)
                    )/x

  ##
  # Take a block of text and use various heuristics to determine it's
  # structure (paragraphs, lists, and so on).  Invoke an event handler as we
  # identify significant chunks.

  def initialize
    @am = RDoc::Markup::AttributeManager.new
    @output = nil
  end

  ##
  # Add to the sequences used to add formatting to an individual word (such
  # as *bold*).  Matching entries will generate attributes that the output
  # formatters can recognize by their +name+.

  def add_word_pair(start, stop, name)
    @am.add_word_pair(start, stop, name)
  end

  ##
  # Add to the sequences recognized as general markup.

  def add_html(tag, name)
    @am.add_html(tag, name)
  end

  ##
  # Add to other inline sequences.  For example, we could add WikiWords using
  # something like:
  #
  #    parser.add_special(/\b([A-Z][a-z]+[A-Z]\w+)/, :WIKIWORD)
  #
  # Each wiki word will be presented to the output formatter via the
  # accept_special method.

  def add_special(pattern, name)
    @am.add_special(pattern, name)
  end

  ##
  # We take a string, split it into lines, work out the type of each line,
  # and from there deduce groups of lines (for example all lines in a
  # paragraph).  We then invoke the output formatter using a Visitor to
  # display the result.

  def convert(str, op)
    lines = str.split(/\r?\n/).map { |line| Line.new line }
    @lines = Lines.new lines

    return "" if @lines.empty?
    @lines.normalize
    assign_types_to_lines
    group = group_lines
    # call the output formatter to handle the result
    #group.each { |line| p line }
    group.accept @am, op
  end

  private

  ##
  # Look through the text at line indentation.  We flag each line as being
  # Blank, a paragraph, a list element, or verbatim text.

  def assign_types_to_lines(margin = 0, level = 0)
    while line = @lines.next
      if line.blank? then
        line.stamp :BLANK, level
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
        line.stamp :RULE, level, $1.length-2
        next
      end

      # Then look for list entries.  First the ones that have to have
      # text following them (* xxx, - xxx, and dd. xxx)

      if SIMPLE_LIST_RE =~ active_line
        offset = margin + $1.length
        prefix = $2
        prefix_length = prefix.length

        flag = case prefix
               when "*","-" then :BULLET
               when /^\d/   then :NUMBER
               when /^[A-Z]/ then :UPPERALPHA
               when /^[a-z]/ then :LOWERALPHA
               else raise "Invalid List Type: #{self.inspect}"
               end

        line.stamp :LIST, level+1, prefix, flag
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
        line.stamp :HEADING, 0, prefix_length
        line.strip_leading(margin + prefix_length)
        next
      end

      # If the character's a space, then we have verbatim text,
      # otherwise

      if active_line[0] == SPACE
        line.strip_leading(margin) if margin > 0
        line.stamp :VERBATIM, level
      else
        line.stamp :PARAGRAPH, level
      end
    end
  end

  ##
  # Handle labeled list entries, We have a special case to deal with.
  # Because the labels can be long, they force the remaining block of text
  # over the to right:
  #
  #   this is a long label that I wrote:: and here is the
  #                                       block of text with
  #                                       a silly margin
  #
  # So we allow the special case.  If the label is followed by nothing, and
  # if the following line is indented, then we take the indent of that line
  # as the new margin.
  #
  #   this is a long label that I wrote::
  #       here is a more reasonably indented block which
  #       will be attached to the label.
  #

  def handled_labeled_list(line, level, margin, offset, prefix)
    prefix_length = prefix.length
    text = line.text
    flag = nil

    case prefix
    when /^\[/ then
      flag = :LABELED
      prefix = prefix[1, prefix.length-2]
    when /:$/ then
      flag = :NOTE
      prefix.chop!
    else
      raise "Invalid List Type: #{self.inspect}"
    end

    # body is on the next line
    if text.length <= offset then
      original_line = line
      line = @lines.next
      return false unless line
      text = line.text

      for i in 0..margin
        if text[i] != SPACE
          @lines.unget
          return false
        end
      end

      i = margin
      i += 1 while text[i] == SPACE

      if i >= text.length then
        @lines.unget
        return false
      else
        offset = i
        prefix_length = 0

        if text[offset..-1] =~ SIMPLE_LIST_RE then
          @lines.unget
          line = original_line
          line.text = ''
        else
          @lines.delete original_line
        end
      end
    end

    line.stamp :LIST, level+1, prefix, flag
    text[margin, prefix_length] = " " * prefix_length
    assign_types_to_lines(offset, level + 1)
    return true
  end

  ##
  # Return a block consisting of fragments which are paragraphs, list
  # entries or verbatim text.  We merge consecutive lines of the same type
  # and level together.  We are also slightly tricky with lists: the lines
  # following a list introduction look like paragraph lines at the next
  # level, and we remap them into list entries instead.

  def group_lines
    @lines.rewind

    in_list = false
    wanted_type = wanted_level = nil

    block = LineCollection.new
    group = nil

    while line = @lines.next
      if line.level == wanted_level and line.type == wanted_type
        group.add_text(line.text)
      else
        group = block.fragment_for(line)
        block.add(group)

        if line.type == :LIST
          wanted_type = :PARAGRAPH
        else
          wanted_type = line.type
        end

        wanted_level = line.type == :HEADING ? line.param : line.level
      end
    end

    block.normalize
    block
  end

  ##
  # For debugging, we allow access to our line contents as text.

  def content
    @lines.as_text
  end
  public :content

  ##
  # For debugging, return the list of line types.

  def get_line_types
    @lines.line_types
  end
  public :get_line_types

end

require 'rdoc/markup/fragments'
require 'rdoc/markup/inline'
require 'rdoc/markup/lines'
