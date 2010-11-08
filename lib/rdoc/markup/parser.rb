require 'strscan'
require 'rdoc/text'

##
# A recursive-descent parser for RDoc markup.
#
# The parser tokenizes an input string then parses the tokens into a Document.
# Documents can be converted into output formats by writing a visitor like
# RDoc::Markup::ToHTML.
#
# The parser only handles the block-level constructs Paragraph, List,
# ListItem, Heading, Verbatim, BlankLine and Rule.  Inline markup such as
# <tt>\+blah\+</tt> is handled separately by RDoc::Markup::AttributeManager.
#
# To see what markup the Parser implements read RDoc.  To see how to use
# RDoc markup to format text in your program read RDoc::Markup.

class RDoc::Markup::Parser

  include RDoc::Text

  ##
  # List token types

  LIST_TOKENS = [
    :BULLET,
    :LABEL,
    :LALPHA,
    :NOTE,
    :NUMBER,
    :UALPHA,
  ]

  ##
  # Parser error subclass

  class Error < RuntimeError; end

  ##
  # Raised when the parser is unable to handle the given markup

  class ParseError < Error; end

  ##
  # Enables display of debugging information

  attr_accessor :debug

  ##
  # Token accessor

  attr_reader :tokens

  ##
  # Parsers +str+ into a Document

  def self.parse str
    parser = new
    #parser.debug = true
    parser.tokenize str
    RDoc::Markup::Document.new(*parser.parse)
  end

  ##
  # Returns a token stream for +str+, for testing

  def self.tokenize str
    parser = new
    parser.tokenize str
    parser.tokens
  end

  ##
  # Creates a new Parser.  See also ::parse

  def initialize
    @tokens = []
    @current_token = nil
    @debug = false

    @line = 0
    @line_pos = 0
  end

  ##
  # Builds a Heading of +level+

  def build_heading level
    heading = RDoc::Markup::Heading.new level, text
    skip :NEWLINE

    heading
  end

  ##
  # Builds a List flush to +margin+

  def build_list margin
    p :list_start => margin if @debug

    list = RDoc::Markup::List.new

    until @tokens.empty? do
      type, data, column, = get

      case type
      when :BULLET, :LABEL, :LALPHA, :NOTE, :NUMBER, :UALPHA then
        list_type = type

        if column < margin then
          unget
          break
        end

        if list.type and list.type != list_type then
          unget
          break
        end

        list.type = list_type

        case type
        when :NOTE, :LABEL then
          _, indent, = get # SPACE
          if :NEWLINE == peek_token.first then
            get
            peek_type, new_indent, peek_column, = peek_token
            indent = new_indent if
              peek_type == :INDENT and peek_column >= column
            unget
          end
        else
          data = nil
          _, indent, = get
        end

        list_item = build_list_item(margin + indent, data)

        list << list_item if list_item
      else
        unget
        break
      end
    end

    p :list_end => margin if @debug

    return nil if list.empty?

    list
  end

  ##
  # Builds a ListItem that is flush to +indent+ with type +item_type+

  def build_list_item indent, item_type = nil
    p :list_item_start => [indent, item_type] if @debug

    list_item = RDoc::Markup::ListItem.new item_type

    until @tokens.empty? do
      type, data, column = get

      if column < indent and
         not type == :NEWLINE and
         (type != :INDENT or data < indent) then
        unget
        break
      end

      case type
      when :INDENT then
        unget
        list_item.push(*parse(indent))
      when :TEXT then
        unget
        list_item << build_paragraph(indent)
      when :HEADER then
        list_item << build_heading(data)
      when :NEWLINE then
        list_item << RDoc::Markup::BlankLine.new
      when *LIST_TOKENS then
        unget
        list_item << build_list(column)
      else
        raise ParseError, "Unhandled token #{@current_token.inspect}"
      end
    end

    p :list_item_end => [indent, item_type] if @debug

    return nil if list_item.empty?

    list_item.parts.shift if
      RDoc::Markup::BlankLine === list_item.parts.first and
      list_item.length > 1

    list_item
  end

  ##
  # Builds a Paragraph that is flush to +margin+

  def build_paragraph margin
    p :paragraph_start => margin if @debug

    paragraph = RDoc::Markup::Paragraph.new

    until @tokens.empty? do
      type, data, column, = get

      case type
      when :INDENT then
        next if data == margin and peek_token[0] == :TEXT

        unget
        break
      when :TEXT then
        if column != margin then
          unget
          break
        end

        paragraph << data
        skip :NEWLINE
      else
        unget
        break
      end
    end

    p :paragraph_end => margin if @debug

    paragraph
  end

  ##
  # Builds a Verbatim that is flush to +margin+

  def build_verbatim margin
    p :verbatim_begin => margin if @debug
    verbatim = RDoc::Markup::Verbatim.new

    until @tokens.empty? do
      type, data, column, = get

      case type
      when :INDENT then
        if margin >= data then
          unget
          break
        end

        indent = data - margin

        verbatim << ' ' * indent
      when :HEADER then
        verbatim << '=' * data

        _, _, peek_column, = peek_token
        peek_column ||= column + data
        verbatim << ' ' * (peek_column - column - data)
      when :RULE then
        width = 2 + data
        verbatim << '-' * width

        _, _, peek_column, = peek_token
        peek_column ||= column + data + 2
        verbatim << ' ' * (peek_column - column - width)
      when :TEXT then
        verbatim << data
      when *LIST_TOKENS then
        if column <= margin then
          unget
          break
        end

        list_marker = case type
                      when :BULLET                   then '*'
                      when :LABEL                    then "[#{data}]"
                      when :LALPHA, :NUMBER, :UALPHA then "#{data}."
                      when :NOTE                     then "#{data}::"
                      end

        verbatim << list_marker

        _, data, = get

        verbatim << ' ' * (data - list_marker.length)
      when :NEWLINE then
        verbatim << data
        break unless [:INDENT, :NEWLINE].include? peek_token[0]
      else
        unget
        break
      end
    end

    verbatim.normalize

    p :verbatim_end => margin if @debug

    verbatim
  end

  ##
  # Pulls the next token from the stream.

  def get
    @current_token = @tokens.shift
    p :get => @current_token if @debug
    @current_token
  end

  ##
  # Parses the tokens into a Document

  def parse indent = 0
    p :parse_start => indent if @debug

    document = []

    until @tokens.empty? do
      type, data, column, = get

      if type != :INDENT and column < indent then
        unget
        break
      end

      case type
      when :HEADER then
        document << build_heading(data)
      when :INDENT then
        if indent > data then
          unget
          break
        elsif indent == data then
          next
        end

        unget
        document << build_verbatim(indent)
      when :NEWLINE then
        document << RDoc::Markup::BlankLine.new
        skip :NEWLINE, false
      when :RULE then
        document << RDoc::Markup::Rule.new(data)
        skip :NEWLINE
      when :TEXT then
        unget
        document << build_paragraph(indent)

        # we're done with this paragraph (indent mismatch)
        break if peek_token[0] == :TEXT
      when *LIST_TOKENS then
        unget

        list = build_list(indent)

        document << list if list

        # we're done with this list (indent mismatch)
        break if LIST_TOKENS.include? peek_token.first and indent > 0
      else
        type, data, column, line = @current_token
        raise ParseError,
              "Unhandled token #{type} (#{data.inspect}) at #{line}:#{column}"
      end
    end

    p :parse_end => indent if @debug

    document
  end

  ##
  # Returns the next token on the stream without modifying the stream

  def peek_token
    token = @tokens.first || []
    p :peek => token if @debug
    token
  end

  ##
  # Skips a token of +token_type+, optionally raising an error.

  def skip token_type, error = true
    type, = get

    return unless type # end of stream

    return @current_token if token_type == type

    unget

    raise ParseError, "expected #{token_type} got #{@current_token.inspect}" if
      error
  end

  ##
  # Consumes tokens until NEWLINE and turns them back into text

  def text
    text = ''

    loop do
      type, data, = get

      text << case type
              when :BULLET then
                _, space, = get # SPACE
                "*#{' ' * (space - 1)}"
              when :LABEL then
                _, space, = get # SPACE
                "[#{data}]#{' ' * (space - data.length - 2)}"
              when :LALPHA, :NUMBER, :UALPHA then
                _, space, = get # SPACE
                "#{data}.#{' ' * (space - 2)}"
              when :NOTE then
                _, space = get # SPACE
                "#{data}::#{' ' * (space - data.length - 2)}"
              when :TEXT then
                data
              when :NEWLINE then
                unget
                break
              when nil then
                break
              else
                raise ParseError, "unhandled token #{@current_token.inspect}"
              end
    end

    text
  end

  ##
  # Calculates the column and line of the current token based on +offset+.

  def token_pos offset
    [offset - @line_pos, @line]
  end

  ##
  # Turns text +input+ into a stream of tokens

  def tokenize input
    s = StringScanner.new input

    @line = 0
    @line_pos = 0

    until s.eos? do
      pos = s.pos

      @tokens << case
                 when s.scan(/\r?\n/) then
                   token = [:NEWLINE, s.matched, *token_pos(pos)]
                   @line_pos = s.pos
                   @line += 1
                   token
                 when s.scan(/ +/) then
                   [:INDENT, s.matched_size, *token_pos(pos)]
                 when s.scan(/(=+)\s*/) then
                   level = s[1].length
                   level = 6 if level > 6
                   @tokens << [:HEADER, level, *token_pos(pos)]

                   pos = s.pos
                   s.scan(/.*/)
                   [:TEXT, s.matched, *token_pos(pos)]
                 when s.scan(/^(-{3,}) *$/) then
                   [:RULE, s[1].length - 2, *token_pos(pos)]
                 when s.scan(/([*-])\s+/) then
                   @tokens << [:BULLET, :BULLET, *token_pos(pos)]
                   [:SPACE, s.matched_size, *token_pos(pos)]
                 when s.scan(/([a-z]|\d+)\.[ \t]+\S/i) then
                   list_label = s[1]
                   width      = s.matched_size - 1

                   s.pos -= 1 # unget \S

                   list_type = case list_label
                               when /[a-z]/ then :LALPHA
                               when /[A-Z]/ then :UALPHA
                               when /\d/    then :NUMBER
                               else
                                 raise ParseError, "BUG token #{list_label}"
                               end

                   @tokens << [list_type, list_label, *token_pos(pos)]
                   [:SPACE, width, *token_pos(pos)]
                 when s.scan(/\[(.*?)\]( +|$)/) then
                   @tokens << [:LABEL, s[1], *token_pos(pos)]
                   [:SPACE, s.matched_size, *token_pos(pos)]
                 when s.scan(/(.*?)::( +|$)/) then
                   @tokens << [:NOTE, s[1], *token_pos(pos)]
                   [:SPACE, s.matched_size, *token_pos(pos)]
                 else s.scan(/.*/)
                   [:TEXT, s.matched, *token_pos(pos)]
                 end
    end

    self
  end

  ##
  # Returns the current token or +token+ to the token stream

  def unget token = @current_token
    p :unget => token if @debug
    raise Error, 'too many #ungets' if token == @tokens.first
    @tokens.unshift token if token
  end

end

require 'rdoc/markup/blank_line'
require 'rdoc/markup/document'
require 'rdoc/markup/heading'
require 'rdoc/markup/list'
require 'rdoc/markup/list_item'
require 'rdoc/markup/raw'
require 'rdoc/markup/paragraph'
require 'rdoc/markup/rule'
require 'rdoc/markup/verbatim'

