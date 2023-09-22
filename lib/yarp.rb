# frozen_string_literal: true

module YARP
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
      "#<YARP::Location @start_offset=#{@start_offset} @length=#{@length} start_line=#{start_line}>"
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
      q.text("(#{start_line},#{start_column})-(#{end_line},#{end_column}))")
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
      new(0, 0)
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
      "#<YARP::Comment @type=#{@type.inspect} @location=#{@location.inspect}>"
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
      "#<YARP::ParseError @message=#{@message.inspect} @location=#{@location.inspect}>"
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
      "#<YARP::ParseWarning @message=#{@message.inspect} @location=#{@location.inspect}>"
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
      q.seplist(inspect.chomp.each_line, -> { q.breakable }) do |line|
        q.text(line.chomp)
      end
      q.current_group.break
    end
  end

  # There are many files in YARP that are templated to handle every node type,
  # which means the files can end up being quite large. We autoload them to make
  # our require speed faster since consuming libraries are unlikely to use all
  # of these features.
  autoload :BasicVisitor, "yarp/visitor"
  autoload :Compiler, "yarp/compiler"
  autoload :Debug, "yarp/debug"
  autoload :DesugarCompiler, "yarp/desugar_compiler"
  autoload :Dispatcher, "yarp/dispatcher"
  autoload :DSL, "yarp/dsl"
  autoload :LexCompat, "yarp/lex_compat"
  autoload :LexRipper, "yarp/lex_compat"
  autoload :MutationCompiler, "yarp/mutation_compiler"
  autoload :NodeInspector, "yarp/node_inspector"
  autoload :RipperCompat, "yarp/ripper_compat"
  autoload :Pack, "yarp/pack"
  autoload :Pattern, "yarp/pattern"
  autoload :Serialize, "yarp/serialize"
  autoload :Visitor, "yarp/visitor"

  # Some of these constants are not meant to be exposed, so marking them as
  # private here.
  private_constant :Debug
  private_constant :LexCompat
  private_constant :LexRipper

  # Returns an array of tokens that closely resembles that of the Ripper lexer.
  # The only difference is that since we don't keep track of lexer state in the
  # same way, it's going to always return the NONE state.
  def self.lex_compat(source, filepath = "")
    LexCompat.new(source, filepath).result
  end

  # This lexes with the Ripper lex. It drops any space events but otherwise
  # returns the same tokens. Raises SyntaxError if the syntax in source is
  # invalid.
  def self.lex_ripper(source)
    LexRipper.new(source).result
  end

  # Load the serialized AST using the source as a reference into a tree.
  def self.load(source, serialized)
    Serialize.load(source, serialized)
  end
end

require_relative "yarp/node"
require_relative "yarp/parse_result/comments"
require_relative "yarp/parse_result/newlines"

# This is a Ruby implementation of the YARP parser. If we're running on CRuby
# and we haven't explicitly set the YARP_FFI_BACKEND environment variable, then
# it's going to require the built library. Otherwise, it's going to require a
# module that uses FFI to call into the library.
if RUBY_ENGINE == "ruby" and !ENV["YARP_FFI_BACKEND"]
  require "yarp/yarp"
else
  require_relative "yarp/ffi"
end

# Reopening the YARP module after yarp/node is required so that constant
# reflection APIs will find the constants defined in the node file before these.
# This block is meant to contain extra APIs we define on YARP nodes that aren't
# templated and are meant as convenience methods.
module YARP
  class FloatNode < Node
    # Returns the value of the node as a Ruby Float.
    def value
      Float(slice)
    end
  end

  class ImaginaryNode < Node
    # Returns the value of the node as a Ruby Complex.
    def value
      Complex(0, numeric.value)
    end
  end

  class IntegerNode < Node
    # Returns the value of the node as a Ruby Integer.
    def value
      Integer(slice)
    end
  end

  class InterpolatedRegularExpressionNode < Node
    # Returns a numeric value that represents the flags that were used to create
    # the regular expression.
    def options
      o = flags & (RegularExpressionFlags::IGNORE_CASE | RegularExpressionFlags::EXTENDED | RegularExpressionFlags::MULTI_LINE)
      o |= Regexp::FIXEDENCODING if flags.anybits?(RegularExpressionFlags::EUC_JP | RegularExpressionFlags::WINDOWS_31J | RegularExpressionFlags::UTF_8)
      o |= Regexp::NOENCODING if flags.anybits?(RegularExpressionFlags::ASCII_8BIT)
      o
    end
  end

  class RationalNode < Node
    # Returns the value of the node as a Ruby Rational.
    def value
      Rational(slice.chomp("r"))
    end
  end

  class RegularExpressionNode < Node
    # Returns a numeric value that represents the flags that were used to create
    # the regular expression.
    def options
      o = flags & (RegularExpressionFlags::IGNORE_CASE | RegularExpressionFlags::EXTENDED | RegularExpressionFlags::MULTI_LINE)
      o |= Regexp::FIXEDENCODING if flags.anybits?(RegularExpressionFlags::EUC_JP | RegularExpressionFlags::WINDOWS_31J | RegularExpressionFlags::UTF_8)
      o |= Regexp::NOENCODING if flags.anybits?(RegularExpressionFlags::ASCII_8BIT)
      o
    end
  end
end
