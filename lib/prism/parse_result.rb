# frozen_string_literal: true
# :markup: markdown
#--
# rbs_inline: enabled

module Prism
  # @rbs!
  #    # An internal interface for a cache that can be used to compute code
  #    # units from byte offsets.
  #    interface _CodeUnitsCache
  #      def []: (Integer byte_offset) -> Integer
  #    end

  # This represents a source of Ruby code that has been parsed. It is used in
  # conjunction with locations to allow them to resolve line numbers and source
  # ranges.
  class Source
    # Create a new source object with the given source code. This method should
    # be used instead of `new` and it will return either a `Source` or a
    # specialized and more performant `ASCIISource` if no multibyte characters
    # are present in the source code.
    #--
    #: (String source, ?Integer start_line, ?Array[Integer] offsets) -> Source
    def self.for(source, start_line = 1, offsets = [])
      if source.ascii_only?
        ASCIISource.new(source, start_line, offsets)
      elsif source.encoding == Encoding::BINARY
        source.force_encoding(Encoding::UTF_8)

        if source.valid_encoding?
          new(source, start_line, offsets)
        else
          # This is an extremely niche use case where the file is marked as
          # binary, contains multi-byte characters, and those characters are not
          # valid UTF-8. In this case we'll mark it as binary and fall back to
          # treating everything as a single-byte character. This _may_ cause
          # problems when asking for code units, but it appears to be the
          # cleanest solution at the moment.
          source.force_encoding(Encoding::BINARY)
          ASCIISource.new(source, start_line, offsets)
        end
      else
        new(source, start_line, offsets)
      end
    end

    # The source code that this source object represents.
    attr_reader :source #: String

    # The line number where this source starts.
    attr_reader :start_line #: Integer

    # The list of newline byte offsets in the source code.
    attr_reader :offsets #: Array[Integer]

    # Create a new source object with the given source code.
    #--
    #: (String source, ?Integer start_line, ?Array[Integer] offsets) -> void
    def initialize(source, start_line = 1, offsets = [])
      @source = source
      @start_line = start_line # set after parsing is done
      @offsets = offsets # set after parsing is done
    end

    # Replace the value of start_line with the given value.
    #--
    #: (Integer start_line) -> void
    def replace_start_line(start_line)
      @start_line = start_line
    end

    # Replace the value of offsets with the given value.
    #--
    #: (Array[Integer] offsets) -> void
    def replace_offsets(offsets)
      @offsets.replace(offsets)
    end

    # Returns the encoding of the source code, which is set by parameters to the
    # parser or by the encoding magic comment.
    #--
    #: () -> Encoding
    def encoding
      source.encoding
    end

    # Returns the lines of the source code as an array of strings.
    #--
    #: () -> Array[String]
    def lines
      source.lines
    end

    # Perform a byteslice on the source code using the given byte offset and
    # byte length.
    #--
    #: (Integer byte_offset, Integer length) -> String
    def slice(byte_offset, length)
      source.byteslice(byte_offset, length) or raise
    end

    # Converts the line number and column in bytes to a byte offset.
    #--
    #: (Integer line, Integer column) -> Integer
    def byte_offset(line, column)
      normal = line - @start_line
      raise IndexError if normal < 0
      offsets.fetch(normal) + column
    rescue IndexError
      raise ArgumentError, "line #{line} is out of range"
    end

    # Binary search through the offsets to find the line number for the given
    # byte offset.
    #--
    #: (Integer byte_offset) -> Integer
    def line(byte_offset)
      start_line + find_line(byte_offset)
    end

    # Return the byte offset of the start of the line corresponding to the given
    # byte offset.
    #--
    #: (Integer byte_offset) -> Integer
    def line_start(byte_offset)
      offsets[find_line(byte_offset)]
    end

    # Returns the byte offset of the end of the line corresponding to the given
    # byte offset.
    #--
    #: (Integer byte_offset) -> Integer
    def line_end(byte_offset)
      offsets[find_line(byte_offset) + 1] || source.bytesize
    end

    # Return the column in bytes for the given byte offset.
    #--
    #: (Integer byte_offset) -> Integer
    def column(byte_offset)
      byte_offset - line_start(byte_offset)
    end

    # Return the character offset for the given byte offset.
    #--
    #: (Integer byte_offset) -> Integer
    def character_offset(byte_offset)
      (source.byteslice(0, byte_offset) or raise).length
    end

    # Return the column in characters for the given byte offset.
    #--
    #: (Integer byte_offset) -> Integer
    def character_column(byte_offset)
      character_offset(byte_offset) - character_offset(line_start(byte_offset))
    end

    # Returns the offset from the start of the file for the given byte offset
    # counting in code units for the given encoding.
    #
    # This method is tested with UTF-8, UTF-16, and UTF-32. If there is the
    # concept of code units that differs from the number of characters in other
    # encodings, it is not captured here.
    #
    # We purposefully replace invalid and undefined characters with replacement
    # characters in this conversion. This happens for two reasons. First, it's
    # possible that the given byte offset will not occur on a character
    # boundary. Second, it's possible that the source code will contain a
    # character that has no equivalent in the given encoding.
    #--
    #: (Integer byte_offset, Encoding encoding) -> Integer
    def code_units_offset(byte_offset, encoding)
      byteslice = (source.byteslice(0, byte_offset) or raise).encode(encoding, invalid: :replace, undef: :replace)

      if encoding == Encoding::UTF_16LE || encoding == Encoding::UTF_16BE
        byteslice.bytesize / 2
      else
        byteslice.length
      end
    end

    # Generate a cache that targets a specific encoding for calculating code
    # unit offsets.
    #--
    #: (Encoding encoding) -> CodeUnitsCache
    def code_units_cache(encoding)
      CodeUnitsCache.new(source, encoding)
    end

    # Returns the column in code units for the given encoding for the
    # given byte offset.
    #--
    #: (Integer byte_offset, Encoding encoding) -> Integer
    def code_units_column(byte_offset, encoding)
      code_units_offset(byte_offset, encoding) - code_units_offset(line_start(byte_offset), encoding)
    end

    # Freeze this object and the objects it contains.
    #--
    #: () -> void
    def deep_freeze
      source.freeze
      offsets.freeze
      freeze
    end

    private

    # Binary search through the offsets to find the line number for the given
    # byte offset.
    #--
    #: (Integer byte_offset) -> Integer
    def find_line(byte_offset) # :nodoc:
      index = offsets.bsearch_index { |offset| offset > byte_offset } || offsets.length
      index - 1
    end
  end

  # A cache that can be used to quickly compute code unit offsets from byte
  # offsets. It purposefully provides only a single #[] method to access the
  # cache in order to minimize surface area.
  #
  # Note that there are some known issues here that may or may not be addressed
  # in the future:
  #
  # * The first is that there are issues when the cache computes values that are
  #   not on character boundaries. This can result in subsequent computations
  #   being off by one or more code units.
  # * The second is that this cache is currently unbounded. In theory we could
  #   introduce some kind of LRU cache to limit the number of entries, but this
  #   has not yet been implemented.
  #
  class CodeUnitsCache
    class UTF16Counter # :nodoc:
      # @rbs @source: String
      # @rbs @encoding: Encoding

      #: (String source, Encoding encoding) -> void
      def initialize(source, encoding)
        @source = source
        @encoding = encoding
      end

      #: (Integer byte_offset, Integer byte_length) -> Integer
      def count(byte_offset, byte_length)
        (@source.byteslice(byte_offset, byte_length) or raise).encode(@encoding, invalid: :replace, undef: :replace).bytesize / 2
      end
    end

    class LengthCounter # :nodoc:
      # @rbs @source: String
      # @rbs @encoding: Encoding

      #: (String source, Encoding encoding) -> void
      def initialize(source, encoding)
        @source = source
        @encoding = encoding
      end

      #: (Integer byte_offset, Integer byte_length) -> Integer
      def count(byte_offset, byte_length)
        (@source.byteslice(byte_offset, byte_length) or raise).encode(@encoding, invalid: :replace, undef: :replace).length
      end
    end

    private_constant :UTF16Counter, :LengthCounter

    # @rbs @source: String
    # @rbs @counter: UTF16Counter | LengthCounter
    # @rbs @cache: Hash[Integer, Integer]
    # @rbs @offsets: Array[Integer]

    # Initialize a new cache with the given source and encoding.
    #--
    #: (String source, Encoding encoding) -> void
    def initialize(source, encoding)
      @source = source
      @counter =
        if encoding == Encoding::UTF_16LE || encoding == Encoding::UTF_16BE
          UTF16Counter.new(source, encoding)
        else
          LengthCounter.new(source, encoding)
        end

      @cache = {} #: Hash[Integer, Integer]
      @offsets = [] #: Array[Integer]
    end

    # Retrieve the code units offset from the given byte offset.
    #--
    #: (Integer byte_offset) -> Integer
    def [](byte_offset)
      @cache[byte_offset] ||=
        if (index = @offsets.bsearch_index { |offset| offset > byte_offset }).nil?
          @offsets << byte_offset
          @counter.count(0, byte_offset)
        elsif index == 0
          @offsets.unshift(byte_offset)
          @counter.count(0, byte_offset)
        else
          @offsets.insert(index, byte_offset)
          offset = @offsets[index - 1]
          @cache[offset] + @counter.count(offset, byte_offset - offset)
        end
    end
  end

  # Specialized version of Prism::Source for source code that includes ASCII
  # characters only. This class is used to apply performance optimizations that
  # cannot be applied to sources that include multibyte characters.
  #
  # In the extremely rare case that a source includes multi-byte characters but
  # is marked as binary because of a magic encoding comment and it cannot be
  # eagerly converted to UTF-8, this class will be used as well. This is because
  # at that point we will treat everything as single-byte characters.
  class ASCIISource < Source
    # Return the character offset for the given byte offset.
    #--
    #: (Integer byte_offset) -> Integer
    def character_offset(byte_offset)
      byte_offset
    end

    # Return the column in characters for the given byte offset.
    #--
    #: (Integer byte_offset) -> Integer
    def character_column(byte_offset)
      byte_offset - line_start(byte_offset)
    end

    # Returns the offset from the start of the file for the given byte offset
    # counting in code units for the given encoding.
    #
    # This method is tested with UTF-8, UTF-16, and UTF-32. If there is the
    # concept of code units that differs from the number of characters in other
    # encodings, it is not captured here.
    #--
    #: (Integer byte_offset, Encoding encoding) -> Integer
    def code_units_offset(byte_offset, encoding)
      byte_offset
    end

    # Returns a cache that is the identity function in order to maintain the
    # same interface. We can do this because code units are always equivalent to
    # byte offsets for ASCII-only sources.
    #--
    #: (Encoding encoding) -> _CodeUnitsCache
    def code_units_cache(encoding)
      ->(byte_offset) { byte_offset }
    end

    # Specialized version of `code_units_column` that does not depend on
    # `code_units_offset`, which is a more expensive operation. This is
    # essentially the same as `Prism::Source#column`.
    #--
    #: (Integer byte_offset, Encoding encoding) -> Integer
    def code_units_column(byte_offset, encoding)
      byte_offset - line_start(byte_offset)
    end
  end

  # This represents a location in the source.
  class Location
    # A Source object that is used to determine more information from the given
    # offset and length.
    attr_reader :source #: Source
    protected :source

    # The byte offset from the beginning of the source where this location
    # starts.
    attr_reader :start_offset #: Integer

    # The length of this location in bytes.
    attr_reader :length #: Integer

    # @rbs @leading_comments: Array[Comment]?
    # @rbs @trailing_comments: Array[Comment]?

    # Create a new location object with the given source, start byte offset, and
    # byte length.
    #--
    #: (Source source, Integer start_offset, Integer length) -> void
    def initialize(source, start_offset, length)
      @source = source
      @start_offset = start_offset
      @length = length

      # These are used to store comments that are associated with this location.
      # They are initialized to `nil` to save on memory when there are no
      # comments to be attached and/or the comment-related APIs are not used.
      @leading_comments = nil
      @trailing_comments = nil
    end

    # These are the comments that are associated with this location that exist
    # before the start of this location.
    #--
    #: () -> Array[Comment]
    def leading_comments
      @leading_comments ||= []
    end

    # Attach a comment to the leading comments of this location.
    #--
    #: (Comment comment) -> void
    def leading_comment(comment)
      leading_comments << comment
    end

    # These are the comments that are associated with this location that exist
    # after the end of this location.
    #--
    #: () -> Array[Comment]
    def trailing_comments
      @trailing_comments ||= []
    end

    # Attach a comment to the trailing comments of this location.
    #--
    #: (Comment comment) -> void
    def trailing_comment(comment)
      trailing_comments << comment
    end

    # Returns all comments that are associated with this location (both leading
    # and trailing comments).
    #--
    #: () -> Array[Comment]
    def comments
      [*@leading_comments, *@trailing_comments] #: Array[Comment]
    end

    # Create a new location object with the given options.
    #--
    #: (?source: Source, ?start_offset: Integer, ?length: Integer) -> Location
    def copy(source: self.source, start_offset: self.start_offset, length: self.length)
      Location.new(source, start_offset, length)
    end

    # Returns a new location that is the result of chopping off the last byte.
    #--
    #: () -> Location
    def chop
      copy(length: length == 0 ? length : length - 1)
    end

    # Returns a string representation of this location.
    #--
    #: () -> String
    def inspect # :nodoc:
      "#<Prism::Location @start_offset=#{@start_offset} @length=#{@length} start_line=#{start_line}>"
    end

    # Returns all of the lines of the source code associated with this location.
    #--
    #: () -> Array[String]
    def source_lines
      source.lines
    end

    # The source code that this location represents.
    #--
    #: () -> String
    def slice
      source.slice(start_offset, length)
    end

    # The source code that this location represents starting from the beginning
    # of the line that this location starts on to the end of the line that this
    # location ends on.
    #--
    #: () -> String
    def slice_lines
      line_start = source.line_start(start_offset)
      line_end = source.line_end(end_offset)
      source.slice(line_start, line_end - line_start)
    end

    # The character offset from the beginning of the source where this location
    # starts.
    #--
    #: () -> Integer
    def start_character_offset
      source.character_offset(start_offset)
    end

    # The offset from the start of the file in code units of the given encoding.
    #--
    #: (Encoding encoding) -> Integer
    def start_code_units_offset(encoding = Encoding::UTF_16LE)
      source.code_units_offset(start_offset, encoding)
    end

    # The start offset from the start of the file in code units using the given
    # cache to fetch or calculate the value.
    #--
    #: (_CodeUnitsCache cache) -> Integer
    def cached_start_code_units_offset(cache)
      cache[start_offset]
    end

    # The byte offset from the beginning of the source where this location ends.
    #--
    #: () -> Integer
    def end_offset
      start_offset + length
    end

    # The character offset from the beginning of the source where this location
    # ends.
    #--
    #: () -> Integer
    def end_character_offset
      source.character_offset(end_offset)
    end

    # The offset from the start of the file in code units of the given encoding.
    #--
    #: (Encoding encoding) -> Integer
    def end_code_units_offset(encoding = Encoding::UTF_16LE)
      source.code_units_offset(end_offset, encoding)
    end

    # The end offset from the start of the file in code units using the given
    # cache to fetch or calculate the value.
    #--
    #: (_CodeUnitsCache cache) -> Integer
    def cached_end_code_units_offset(cache)
      cache[end_offset]
    end

    # The line number where this location starts.
    #--
    #: () -> Integer
    def start_line
      source.line(start_offset)
    end

    # The content of the line where this location starts before this location.
    #--
    #: () -> String
    def start_line_slice
      offset = source.line_start(start_offset)
      source.slice(offset, start_offset - offset)
    end

    # The line number where this location ends.
    #--
    #: () -> Integer
    def end_line
      source.line(end_offset)
    end

    # The column in bytes where this location starts from the start of
    # the line.
    #--
    #: () -> Integer
    def start_column
      source.column(start_offset)
    end

    # The column in characters where this location ends from the start of
    # the line.
    #--
    #: () -> Integer
    def start_character_column
      source.character_column(start_offset)
    end

    # The column in code units of the given encoding where this location
    # starts from the start of the line.
    #--
    #: (?Encoding encoding) -> Integer
    def start_code_units_column(encoding = Encoding::UTF_16LE)
      source.code_units_column(start_offset, encoding)
    end

    # The start column in code units using the given cache to fetch or calculate
    # the value.
    #--
    #: (_CodeUnitsCache cache) -> Integer
    def cached_start_code_units_column(cache)
      cache[start_offset] - cache[source.line_start(start_offset)]
    end

    # The column in bytes where this location ends from the start of the
    # line.
    #--
    #: () -> Integer
    def end_column
      source.column(end_offset)
    end

    # The column in characters where this location ends from the start of
    # the line.
    #--
    #: () -> Integer
    def end_character_column
      source.character_column(end_offset)
    end

    # The column in code units of the given encoding where this location
    # ends from the start of the line.
    #--
    #: (?Encoding encoding) -> Integer
    def end_code_units_column(encoding = Encoding::UTF_16LE)
      source.code_units_column(end_offset, encoding)
    end

    # The end column in code units using the given cache to fetch or calculate
    # the value.
    #--
    #: (_CodeUnitsCache cache) -> Integer
    def cached_end_code_units_column(cache)
      cache[end_offset] - cache[source.line_start(end_offset)]
    end

    # Implement the hash pattern matching interface for Location.
    #--
    #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
    def deconstruct_keys(keys) # :nodoc:
      { start_offset: start_offset, end_offset: end_offset }
    end

    # Implement the pretty print interface for Location.
    #--
    #: (PP q) -> void
    def pretty_print(q) # :nodoc:
      q.text("(#{start_line},#{start_column})-(#{end_line},#{end_column})")
    end

    # Returns true if the given other location is equal to this location.
    #--
    #: (untyped other) -> bool
    def ==(other)
      Location === other &&
        other.start_offset == start_offset &&
        other.end_offset == end_offset
    end

    # Returns a new location that stretches from this location to the given
    # other location. Raises an error if this location is not before the other
    # location or if they don't share the same source.
    #--
    #: (Location other) -> Location
    def join(other)
      raise "Incompatible sources" if source != other.source
      raise "Incompatible locations" if start_offset > other.start_offset

      Location.new(source, start_offset, other.end_offset - start_offset)
    end

    # Join this location with the first occurrence of the string in the source
    # that occurs after this location on the same line, and return the new
    # location. This will raise an error if the string does not exist.
    #--
    #: (String string) -> Location
    def adjoin(string)
      line_suffix = source.slice(end_offset, source.line_end(end_offset) - end_offset)

      line_suffix_index = line_suffix.byteindex(string)
      raise "Could not find #{string}" if line_suffix_index.nil?

      Location.new(source, start_offset, length + line_suffix_index + string.bytesize)
    end
  end

  # This represents a comment that was encountered during parsing. It is the
  # base class for all comment types.
  class Comment
    # The Location of this comment in the source.
    attr_reader :location #: Location

    # Create a new comment object with the given location.
    #--
    #: (Location location) -> void
    def initialize(location)
      @location = location
    end

    # Implement the hash pattern matching interface for Comment.
    #--
    #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
    def deconstruct_keys(keys) # :nodoc:
      { location: location }
    end

    # Returns the content of the comment by slicing it from the source code.
    #--
    #: () -> String
    def slice
      location.slice
    end

    # Returns true if this comment happens on the same line as other code and
    # false if the comment is by itself. This can only be true for inline
    # comments and should be false for block comments.
    #--
    #: () -> bool
    def trailing?
      raise NotImplementedError, "trailing? is not implemented for #{self.class}"
    end
  end

  # InlineComment objects are the most common. They correspond to comments in
  # the source file like this one that start with #.
  class InlineComment < Comment
    # Returns true if this comment happens on the same line as other code and
    # false if the comment is by itself.
    #--
    #: () -> bool
    def trailing?
      !location.start_line_slice.strip.empty?
    end

    # Returns a string representation of this comment.
    #--
    #: () -> String
    def inspect # :nodoc:
      "#<Prism::InlineComment @location=#{location.inspect}>"
    end
  end

  # EmbDocComment objects correspond to comments that are surrounded by =begin
  # and =end.
  class EmbDocComment < Comment
    # Returns false. This can only be true for inline comments.
    #--
    #: () -> bool
    def trailing?
      false
    end

    # Returns a string representation of this comment.
    #--
    #: () -> String
    def inspect # :nodoc:
      "#<Prism::EmbDocComment @location=#{location.inspect}>"
    end
  end

  # This represents a magic comment that was encountered during parsing.
  class MagicComment
    # A Location object representing the location of the key in the source.
    attr_reader :key_loc #: Location

    # A Location object representing the location of the value in the source.
    attr_reader :value_loc #: Location

    # Create a new magic comment object with the given key and value locations.
    #--
    #: (Location key_loc, Location value_loc) -> void
    def initialize(key_loc, value_loc)
      @key_loc = key_loc
      @value_loc = value_loc
    end

    # Returns the key of the magic comment by slicing it from the source code.
    #--
    #: () -> String
    def key
      key_loc.slice
    end

    # Returns the value of the magic comment by slicing it from the source code.
    #--
    #: () -> String
    def value
      value_loc.slice
    end

    # Implement the hash pattern matching interface for MagicComment.
    #--
    #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
    def deconstruct_keys(keys) # :nodoc:
      { key_loc: key_loc, value_loc: value_loc }
    end

    # Returns a string representation of this magic comment.
    #--
    #: () -> String
    def inspect # :nodoc:
      "#<Prism::MagicComment @key=#{key.inspect} @value=#{value.inspect}>"
    end
  end

  # This represents an error that was encountered during parsing.
  class ParseError
    # The type of error. This is an _internal_ symbol that is used for
    # communicating with translation layers. It is not meant to be public API.
    attr_reader :type #: Symbol

    # The message associated with this error.
    attr_reader :message #: String

    # A Location object representing the location of this error in the source.
    attr_reader :location #: Location

    # The level of this error.
    attr_reader :level #: Symbol

    # Create a new error object with the given message and location.
    #--
    #: (Symbol type, String message, Location location, Symbol level) -> void
    def initialize(type, message, location, level)
      @type = type
      @message = message
      @location = location
      @level = level
    end

    # Implement the hash pattern matching interface for ParseError.
    #--
    #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
    def deconstruct_keys(keys) # :nodoc:
      { type: type, message: message, location: location, level: level }
    end

    # Returns a string representation of this error.
    #--
    #: () -> String
    def inspect # :nodoc:
      "#<Prism::ParseError @type=#{@type.inspect} @message=#{@message.inspect} @location=#{@location.inspect} @level=#{@level.inspect}>"
    end
  end

  # This represents a warning that was encountered during parsing.
  class ParseWarning
    # The type of warning. This is an _internal_ symbol that is used for
    # communicating with translation layers. It is not meant to be public API.
    attr_reader :type #: Symbol

    # The message associated with this warning.
    attr_reader :message #: String

    # A Location object representing the location of this warning in the source.
    attr_reader :location #: Location

    # The level of this warning.
    attr_reader :level #: Symbol

    # Create a new warning object with the given message and location.
    #--
    #: (Symbol type, String message, Location location, Symbol level) -> void
    def initialize(type, message, location, level)
      @type = type
      @message = message
      @location = location
      @level = level
    end

    # Implement the hash pattern matching interface for ParseWarning.
    #--
    #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
    def deconstruct_keys(keys) # :nodoc:
      { type: type, message: message, location: location, level: level }
    end

    # Returns a string representation of this warning.
    #--
    #: () -> String
    def inspect # :nodoc:
      "#<Prism::ParseWarning @type=#{@type.inspect} @message=#{@message.inspect} @location=#{@location.inspect} @level=#{@level.inspect}>"
    end
  end

  # This represents the result of a call to Prism.parse or Prism.parse_file.
  # It contains the requested structure, any comments that were encounters,
  # and any errors that were encountered.
  class Result
    # The list of comments that were encountered during parsing.
    attr_reader :comments #: Array[Comment]

    # The list of magic comments that were encountered during parsing.
    attr_reader :magic_comments #: Array[MagicComment]

    # An optional location that represents the location of the __END__ marker
    # and the rest of the content of the file. This content is loaded into the
    # DATA constant when the file being parsed is the main file being executed.
    attr_reader :data_loc #: Location?

    # The list of errors that were generated during parsing.
    attr_reader :errors #: Array[ParseError]

    # The list of warnings that were generated during parsing.
    attr_reader :warnings #: Array[ParseWarning]

    # A Source instance that represents the source code that was parsed.
    attr_reader :source #: Source

    # Create a new result object with the given values.
    #--
    #: (Array[Comment] comments, Array[MagicComment] magic_comments, Location? data_loc, Array[ParseError] errors, Array[ParseWarning] warnings, Source source) -> void
    def initialize(comments, magic_comments, data_loc, errors, warnings, source)
      @comments = comments
      @magic_comments = magic_comments
      @data_loc = data_loc
      @errors = errors
      @warnings = warnings
      @source = source
    end

    # Implement the hash pattern matching interface for Result.
    #--
    #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
    def deconstruct_keys(keys) # :nodoc:
      { comments: comments, magic_comments: magic_comments, data_loc: data_loc, errors: errors, warnings: warnings }
    end

    # Returns the encoding of the source code that was parsed.
    #--
    #: () -> Encoding
    def encoding
      source.encoding
    end

    # Returns true if there were no errors during parsing and false if there
    # were.
    #--
    #: () -> bool
    def success?
      errors.empty?
    end

    # Returns true if there were errors during parsing and false if there were
    # not.
    #--
    #: () -> bool
    def failure?
      !success?
    end

    # Create a code units cache for the given encoding.
    #--
    #: (Encoding encoding) -> _CodeUnitsCache
    def code_units_cache(encoding)
      source.code_units_cache(encoding)
    end
  end

  # This is a result specific to the `parse` and `parse_file` methods.
  class ParseResult < Result
    autoload :Comments, "prism/parse_result/comments"
    autoload :Errors, "prism/parse_result/errors"
    autoload :Newlines, "prism/parse_result/newlines"

    private_constant :Comments
    private_constant :Errors
    private_constant :Newlines

    # The syntax tree that was parsed from the source code.
    attr_reader :value #: ProgramNode

    # Create a new parse result object with the given values.
    #--
    #: (ProgramNode value, Array[Comment] comments, Array[MagicComment] magic_comments, Location? data_loc, Array[ParseError] errors, Array[ParseWarning] warnings, Source source) -> void
    def initialize(value, comments, magic_comments, data_loc, errors, warnings, source)
      @value = value
      super(comments, magic_comments, data_loc, errors, warnings, source)
    end

    # Implement the hash pattern matching interface for ParseResult.
    #--
    #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
    def deconstruct_keys(keys) # :nodoc:
      super.merge!(value: value)
    end

    # Attach the list of comments to their respective locations in the tree.
    #--
    #: () -> void
    def attach_comments!
      Comments.new(self).attach! # steep:ignore
    end

    # Walk the tree and mark nodes that are on a new line, loosely emulating
    # the behavior of CRuby's `:line` tracepoint event.
    #--
    #: () -> void
    def mark_newlines!
      value.accept(Newlines.new(source.offsets.size)) # steep:ignore
    end

    # Returns a string representation of the syntax tree with the errors
    # displayed inline.
    #--
    #: () -> String
    def errors_format
      Errors.new(self).format
    end
  end

  # This is a result specific to the `lex` and `lex_file` methods.
  class LexResult < Result
    # The list of tokens that were parsed from the source code.
    attr_reader :value #: Array[[Token, Integer]]

    # Create a new lex result object with the given values.
    #--
    #: (Array[[Token, Integer]] value, Array[Comment] comments, Array[MagicComment] magic_comments, Location? data_loc, Array[ParseError] errors, Array[ParseWarning] warnings, Source source) -> void
    def initialize(value, comments, magic_comments, data_loc, errors, warnings, source)
      @value = value
      super(comments, magic_comments, data_loc, errors, warnings, source)
    end

    # Implement the hash pattern matching interface for LexResult.
    #--
    #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
    def deconstruct_keys(keys) # :nodoc:
      super.merge!(value: value)
    end
  end

  # This is a result specific to the `parse_lex` and `parse_lex_file` methods.
  class ParseLexResult < Result
    # A tuple of the syntax tree and the list of tokens that were parsed from
    # the source code.
    attr_reader :value #: [ProgramNode, Array[[Token, Integer]]]

    # Create a new parse lex result object with the given values.
    #--
    #: ([ProgramNode, Array[[Token, Integer]]] value, Array[Comment] comments, Array[MagicComment] magic_comments, Location? data_loc, Array[ParseError] errors, Array[ParseWarning] warnings, Source source) -> void
    def initialize(value, comments, magic_comments, data_loc, errors, warnings, source)
      @value = value
      super(comments, magic_comments, data_loc, errors, warnings, source)
    end

    # Implement the hash pattern matching interface for ParseLexResult.
    #--
    #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
    def deconstruct_keys(keys) # :nodoc:
      super.merge!(value: value)
    end
  end

  # This represents a token from the Ruby source.
  class Token
    # The Source object that represents the source this token came from.
    attr_reader :source #: Source
    private :source

    # The type of token that this token is.
    attr_reader :type #: Symbol

    # A byteslice of the source that this token represents.
    attr_reader :value #: String

    # @rbs @location: Location | Integer

    # Create a new token object with the given type, value, and location.
    #--
    #: (Source source, Symbol type, String value, Location | Integer location) -> void
    def initialize(source, type, value, location)
      @source = source
      @type = type
      @value = value
      @location = location
    end

    # Implement the hash pattern matching interface for Token.
    #--
    #: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
    def deconstruct_keys(keys) # :nodoc:
      { type: type, value: value, location: location }
    end

    # A Location object representing the location of this token in the source.
    #--
    #: () -> Location
    def location
      location = @location
      return location if location.is_a?(Location)
      @location = Location.new(source, location >> 32, location & 0xFFFFFFFF)
    end

    # Implement the pretty print interface for Token.
    #--
    #: (PP q) -> void
    def pretty_print(q) # :nodoc:
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

    # Returns true if the given other token is equal to this token.
    #--
    #: (untyped other) -> bool
    def ==(other)
      Token === other &&
        other.type == type &&
        other.value == value
    end

    # Returns a string representation of this token.
    #--
    #: () -> String
    def inspect # :nodoc:
      location
      super
    end

    # Freeze this object and the objects it contains.
    #--
    #: () -> void
    def deep_freeze
      value.freeze
      location.freeze
      freeze
    end
  end

  # This object is passed to the various Prism.* methods that accept the
  # `scopes` option as an element of the list. It defines both the local
  # variables visible at that scope as well as the forwarding parameters
  # available at that scope.
  class Scope
    # The list of local variables that are defined in this scope. This should be
    # defined as an array of symbols.
    attr_reader :locals #: Array[Symbol]

    # The list of local variables that are forwarded to the next scope. This
    # should by defined as an array of symbols containing the specific values of
    # :*, :**, :&, or :"...".
    attr_reader :forwarding #: Array[Symbol]

    # Create a new scope object with the given locals and forwarding.
    #--
    #: (Array[Symbol] locals, Array[Symbol] forwarding) -> void
    def initialize(locals, forwarding)
      @locals = locals
      @forwarding = forwarding
    end
  end

  # Create a new scope with the given locals and forwarding options that is
  # suitable for passing into one of the Prism.* methods that accepts the
  # `scopes` option.
  #--
  #: (?locals: Array[Symbol], ?forwarding: Array[Symbol]) -> Scope
  def self.scope(locals: [], forwarding: [])
    Scope.new(locals, forwarding)
  end
end
