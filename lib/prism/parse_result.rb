# frozen_string_literal: true

module Prism
  # This represents a source of Ruby code that has been parsed. It is used in
  # conjunction with locations to allow them to resolve line numbers and source
  # ranges.
  class Source
    attr_reader :source, :offsets

    def initialize(source, offsets = compute_offsets(source))
      @source = source
      @offsets = offsets
    end

    def slice(offset, length)
      source.byteslice(offset, length)
    end

    def line(value)
      offsets.bsearch_index { |offset| offset > value } || offsets.length
    end

    def line_offset(value)
      offsets[line(value) - 1]
    end

    def column(value)
      value - offsets[line(value) - 1]
    end

    private

    def compute_offsets(code)
      offsets = [0]
      code.b.scan("\n") { offsets << $~.end(0) }
      offsets
    end
  end

  # This represents a location in the source.
  class Location
    # A Source object that is used to determine more information from the given
    # offset and length.
    protected attr_reader :source

    # The byte offset from the beginning of the source where this location
    # starts.
    attr_reader :start_offset

    # The length of this location in bytes.
    attr_reader :length

    # The list of comments attached to this location
    attr_reader :comments

    def initialize(source, start_offset, length)
      @source = source
      @start_offset = start_offset
      @length = length
      @comments = []
    end

    # Create a new location object with the given options.
    def copy(**options)
      Location.new(
        options.fetch(:source) { source },
        options.fetch(:start_offset) { start_offset },
        options.fetch(:length) { length }
      )
    end

    # Returns a string representation of this location.
    def inspect
      "#<Prism::Location @start_offset=#{@start_offset} @length=#{@length} start_line=#{start_line}>"
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

    # The content of the line where this location starts before this location.
    def start_line_slice
      offset = source.line_offset(start_offset)
      source.slice(offset, start_offset - offset)
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
      source.column(end_offset)
    end

    def deconstruct_keys(keys)
      { start_offset: start_offset, end_offset: end_offset }
    end

    def pretty_print(q)
      q.text("(#{start_line},#{start_column})-(#{end_line},#{end_column})")
    end

    def ==(other)
      other.is_a?(Location) &&
        other.start_offset == start_offset &&
        other.end_offset == end_offset
    end

    # Returns a new location that stretches from this location to the given
    # other location. Raises an error if this location is not before the other
    # location or if they don't share the same source.
    def join(other)
      raise "Incompatible sources" if source != other.source
      raise "Incompatible locations" if start_offset > other.start_offset

      Location.new(source, start_offset, other.end_offset - start_offset)
    end

    def self.null
      new(nil, 0, 0)
    end
  end

  # This represents a comment that was encountered during parsing.
  class Comment
    TYPES = [:inline, :embdoc, :__END__]

    attr_reader :type, :location

    def initialize(type, location)
      @type = type
      @location = location
    end

    def deconstruct_keys(keys)
      { type: type, location: location }
    end

    # Returns true if the comment happens on the same line as other code and false if the comment is by itself
    def trailing?
      type == :inline && !location.start_line_slice.strip.empty?
    end

    def inspect
      "#<Prism::Comment @type=#{@type.inspect} @location=#{@location.inspect}>"
    end
  end

  # This represents a magic comment that was encountered during parsing.
  class MagicComment
    attr_reader :key_loc, :value_loc

    def initialize(key_loc, value_loc)
      @key_loc = key_loc
      @value_loc = value_loc
    end

    def key
      key_loc.slice
    end

    def value
      value_loc.slice
    end

    def deconstruct_keys(keys)
      { key_loc: key_loc, value_loc: value_loc }
    end

    def inspect
      "#<Prism::MagicComment @key=#{key.inspect} @value=#{value.inspect}>"
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

    def inspect
      "#<Prism::ParseError @message=#{@message.inspect} @location=#{@location.inspect}>"
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

    def inspect
      "#<Prism::ParseWarning @message=#{@message.inspect} @location=#{@location.inspect}>"
    end
  end

  # This represents the result of a call to ::parse or ::parse_file. It contains
  # the AST, any comments that were encounters, and any errors that were
  # encountered.
  class ParseResult
    attr_reader :value, :comments, :magic_comments, :errors, :warnings, :source

    def initialize(value, comments, magic_comments, errors, warnings, source)
      @value = value
      @comments = comments
      @magic_comments = magic_comments
      @errors = errors
      @warnings = warnings
      @source = source
    end

    def deconstruct_keys(keys)
      { value: value, comments: comments, magic_comments: magic_comments, errors: errors, warnings: warnings }
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
end
