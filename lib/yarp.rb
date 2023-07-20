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

    def pretty_print(q)
      q.group do
        q.text(self.class.name.split("::").last)
        location.pretty_print(q)
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

  def self.newlines(source)
    YARP.parse(source).source.offsets
  end
end

require_relative "yarp/lex_compat"
require_relative "yarp/node"
require_relative "yarp/ripper_compat"
require_relative "yarp/serialize"
require_relative "yarp/pack"
require "yarp.so"
