# frozen_string_literal: true

module YARP
  # This represents a source of Ruby code that has been parsed. It is used in
  # conjunction with locations to allow them to resolve line numbers and source
  # ranges.
  class Source
    attr_reader :source, :offsets

    def initialize(source, offsets)
      @source = source
      @offsets = offsets
    end

    def slice(offset, length)
      source.byteslice(offset, length)
    end

    def line(value)
      offsets.bsearch_index { |offset| offset > value } || offsets.length
    end

    def column(value)
      value - offsets[line(value) - 1]
    end
  end

  # This represents a location in the source.
  class Location
    # A Source object that is used to determine more information from the given
    # offset and length.
    private attr_reader :source

    # The byte offset from the beginning of the source where this location
    # starts.
    attr_reader :start_offset

    # The length of this location in bytes.
    attr_reader :length

    def initialize(source, start_offset, length)
      @source = source
      @start_offset = start_offset
      @length = length
    end

    def inspect
      "#<YARP::Location @start_offset=#{@start_offset} @length=#{@length}>"
    end

    # The source code that this location represents.
    def slice
      source.slice(start_offset, length)
    end

    # The byte offset from the beginning of the source where this location ends.
    def end_offset
      start_offset + length
    end

    # The line number where this location starts.
    def start_line
      source.line(start_offset)
    end

    # The line number where this location ends.
    def end_line
      source.line(end_offset - 1)
    end

    # The column number in bytes where this location starts from the start of
    # the line.
    def start_column
      source.column(start_offset)
    end

    # The column number in bytes where this location ends from the start of the
    # line.
    def end_column
      source.column(end_offset - 1)
    end

    def deconstruct_keys(keys)
      { start_offset: start_offset, end_offset: end_offset }
    end

    def pretty_print(q)
      q.text("(#{start_offset}...#{end_offset})")
    end

    def ==(other)
      other.is_a?(Location) &&
        other.start_offset == start_offset &&
        other.end_offset == end_offset
    end

    def self.null
      new(0, 0)
    end
  end

  # This represents a comment that was encountered during parsing.
  class Comment
    attr_reader :type, :location

    def initialize(type, location)
      @type = type
      @location = location
    end

    def deconstruct_keys(keys)
      { type: type, location: location }
    end
  end

  # This represents an error that was encountered during parsing.
  class ParseError
    attr_reader :message, :location

    def initialize(message, location)
      @message = message
      @location = location
    end

    def deconstruct_keys(keys)
      { message: message, location: location }
    end
  end

  # This represents a warning that was encountered during parsing.
  class ParseWarning
    attr_reader :message, :location

    def initialize(message, location)
      @message = message
      @location = location
    end

    def deconstruct_keys(keys)
      { message: message, location: location }
    end
  end

  # A class that knows how to walk down the tree. None of the individual visit
  # methods are implemented on this visitor, so it forces the consumer to
  # implement each one that they need. For a default implementation that
  # continues walking the tree, see the Visitor class.
  class BasicVisitor
    def visit(node)
      node&.accept(self)
    end

    def visit_all(nodes)
      nodes.map { |node| visit(node) }
    end

    def visit_child_nodes(node)
      visit_all(node.child_nodes)
    end
  end

  class Visitor < BasicVisitor
  end

  # This represents the result of a call to ::parse or ::parse_file. It contains
  # the AST, any comments that were encounters, and any errors that were
  # encountered.
  class ParseResult
    attr_reader :value, :comments, :errors, :warnings, :source

    def initialize(value, comments, errors, warnings, source)
      @value = value
      @comments = comments
      @errors = errors
      @warnings = warnings
      @source = source
    end

    def deconstruct_keys(keys)
      { value: value, comments: comments, errors: errors, warnings: warnings }
    end

    def success?
      errors.empty?
    end

    def failure?
      !success?
    end

    # Keep in sync with Java MarkNewlinesVisitor
    class MarkNewlinesVisitor < YARP::Visitor
      def initialize(newline_marked)
        @newline_marked = newline_marked
      end

      def visit_block_node(node)
        old_newline_marked = @newline_marked
        @newline_marked = Array.new(old_newline_marked.size, false)
        begin
          super(node)
        ensure
          @newline_marked = old_newline_marked
        end
      end
      alias_method :visit_lambda_node, :visit_block_node

      def visit_if_node(node)
        node.set_newline_flag(@newline_marked)
        super(node)
      end
      alias_method :visit_unless_node, :visit_if_node

      def visit_statements_node(node)
        node.body.each do |child|
          child.set_newline_flag(@newline_marked)
        end
        super(node)
      end
    end
    private_constant :MarkNewlinesVisitor

    def mark_newlines
      newline_marked = Array.new(1 + @source.offsets.size, false)
      visitor = MarkNewlinesVisitor.new(newline_marked)
      value.accept(visitor)
      value
    end
  end

  # This represents a token from the Ruby source.
  class Token
    attr_reader :type, :value, :location

    def initialize(type, value, location)
      @type = type
      @value = value
      @location = location
    end

    def deconstruct_keys(keys)
      { type: type, value: value, location: location }
    end

    def pretty_print(q)
      q.group do
        q.text(type.to_s)
        self.location.pretty_print(q)
        q.text("(")
        q.nest(2) do
          q.breakable("")
          q.pp(value)
        end
        q.breakable("")
        q.text(")")
      end
    end

    def ==(other)
      other.is_a?(Token) &&
        other.type == type &&
        other.value == value
    end
  end

  # This represents a node in the tree.
  class Node
    attr_reader :location

    def newline?
      @newline ? true : false
    end

    def set_newline_flag(newline_marked)
      line = location.start_line
      unless newline_marked[line]
        newline_marked[line] = true
        @newline = true
      end
    end

    # Slice the location of the node from the source.
    def slice
      location.slice
    end

    def pretty_print(q)
      q.group do
        q.text(self.class.name.split("::").last)
        location.pretty_print(q)
        q.text("[Li:#{location.start_line}]") if newline?
        q.text("(")
        q.nest(2) do
          deconstructed = deconstruct_keys([])
          deconstructed.delete(:location)

          q.breakable("")
          q.seplist(deconstructed, lambda { q.comma_breakable }, :each_value) { |value| q.pp(value) }
        end
        q.breakable("")
        q.text(")")
      end
    end
  end

  # Load the serialized AST using the source as a reference into a tree.
  def self.load(source, serialized)
    Serialize.load(source, serialized)
  end

  # This module is used for testing and debugging and is not meant to be used by
  # consumers of this library.
  module Debug
    def self.newlines(source)
      YARP.parse(source).source.offsets
    end

    def self.parse_serialize_file(filepath)
      parse_serialize_file_metadata(filepath, [filepath.bytesize, filepath.b, 0].pack("LA*L"))
    end
  end

  # Marking this as private so that consumers don't see it. It makes it a little
  # annoying for testing since you have to const_get it to access the methods,
  # but at least this way it's clear it's not meant for consumers.
  private_constant :Debug
end

require_relative "yarp/lex_compat"
require_relative "yarp/node"
require_relative "yarp/ripper_compat"
require_relative "yarp/serialize"
require_relative "yarp/pack"

require "yarp/yarp"
