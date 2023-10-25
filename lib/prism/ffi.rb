# frozen_string_literal: true

# This file is responsible for mirroring the API provided by the C extension by
# using FFI to call into the shared library.

require "rbconfig"
require "ffi"

module Prism
  BACKEND = :FFI

  module LibRubyParser
    extend FFI::Library

    # Define the library that we will be pulling functions from. Note that this
    # must align with the build shared library from make/rake.
    ffi_lib File.expand_path("../../build/librubyparser.#{RbConfig::CONFIG["SOEXT"]}", __dir__)

    # Convert a native C type declaration into a symbol that FFI understands.
    # For example:
    #
    #     const char * -> :pointer
    #     bool         -> :bool
    #     size_t       -> :size_t
    #     void         -> :void
    #
    def self.resolve_type(type)
      type = type.strip
      type.end_with?("*") ? :pointer : type.delete_prefix("const ").to_sym
    end

    # Read through the given header file and find the declaration of each of the
    # given functions. For each one, define a function with the same name and
    # signature as the C function.
    def self.load_exported_functions_from(header, *functions)
      File.foreach(File.expand_path("../../include/#{header}", __dir__)) do |line|
        # We only want to attempt to load exported functions.
        next unless line.start_with?("PRISM_EXPORTED_FUNCTION ")

        # We only want to load the functions that we are interested in.
        next unless functions.any? { |function| line.include?(function) }

        # Parse the function declaration.
        unless /^PRISM_EXPORTED_FUNCTION (?<return_type>.+) (?<name>\w+)\((?<arg_types>.+)\);$/ =~ line
          raise "Could not parse #{line}"
        end

        # Delete the function from the list of functions we are looking for to
        # mark it as having been found.
        functions.delete(name)

        # Split up the argument types into an array, ensure we handle the case
        # where there are no arguments (by explicit void).
        arg_types = arg_types.split(",").map(&:strip)
        arg_types = [] if arg_types == %w[void]

        # Resolve the type of the argument by dropping the name of the argument
        # first if it is present.
        arg_types.map! { |type| resolve_type(type.sub(/\w+$/, "")) }

        # Attach the function using the FFI library.
        attach_function name, arg_types, resolve_type(return_type)
      end

      # If we didn't find all of the functions, raise an error.
      raise "Could not find functions #{functions.inspect}" unless functions.empty?
    end

    load_exported_functions_from(
      "prism.h",
      "pm_version",
      "pm_parse_serialize",
      "pm_lex_serialize",
      "pm_parse_lex_serialize"
    )

    load_exported_functions_from(
      "prism/util/pm_buffer.h",
      "pm_buffer_sizeof",
      "pm_buffer_init",
      "pm_buffer_value",
      "pm_buffer_length",
      "pm_buffer_free"
    )

    load_exported_functions_from(
      "prism/util/pm_string.h",
      "pm_string_mapped_init",
      "pm_string_free",
      "pm_string_source",
      "pm_string_length",
      "pm_string_sizeof"
    )

    # This object represents a pm_buffer_t. We only use it as an opaque pointer,
    # so it doesn't need to know the fields of pm_buffer_t.
    class PrismBuffer
      SIZEOF = LibRubyParser.pm_buffer_sizeof

      attr_reader :pointer

      def initialize(pointer)
        @pointer = pointer
      end

      def value
        LibRubyParser.pm_buffer_value(pointer)
      end

      def length
        LibRubyParser.pm_buffer_length(pointer)
      end

      def read
        value.read_string(length)
      end

      # Initialize a new buffer and yield it to the block. The buffer will be
      # automatically freed when the block returns.
      def self.with(&block)
        pointer = FFI::MemoryPointer.new(SIZEOF)

        begin
          raise unless LibRubyParser.pm_buffer_init(pointer)
          yield new(pointer)
        ensure
          LibRubyParser.pm_buffer_free(pointer)
          pointer.free
        end
      end
    end

    # This object represents a pm_string_t. We only use it as an opaque pointer,
    # so it doesn't have to be an FFI::Struct.
    class PrismString
      SIZEOF = LibRubyParser.pm_string_sizeof

      attr_reader :pointer

      def initialize(pointer)
        @pointer = pointer
      end

      def source
        LibRubyParser.pm_string_source(pointer)
      end

      def length
        LibRubyParser.pm_string_length(pointer)
      end

      def read
        source.read_string(length)
      end

      # Yields a pm_string_t pointer to the given block.
      def self.with(filepath, &block)
        pointer = FFI::MemoryPointer.new(SIZEOF)

        begin
          raise unless LibRubyParser.pm_string_mapped_init(pointer, filepath)
          yield new(pointer)
        ensure
          LibRubyParser.pm_string_free(pointer)
          pointer.free
        end
      end
    end

    def self.dump_internal(source, source_size, filepath)
      PrismBuffer.with do |buffer|
        metadata = [filepath.bytesize, filepath.b, 0].pack("LA*L") if filepath
        pm_parse_serialize(source, source_size, buffer.pointer, metadata)
        buffer.read
      end
    end
  end

  # Mark the LibRubyParser module as private as it should only be called through
  # the prism module.
  private_constant :LibRubyParser

  # The version constant is set by reading the result of calling pm_version.
  VERSION = LibRubyParser.pm_version.read_string

  # Mirror the Prism.dump API by using the serialization API.
  def self.dump(code, filepath = nil)
    LibRubyParser.dump_internal(code, code.bytesize, filepath)
  end

  # Mirror the Prism.dump_file API by using the serialization API.
  def self.dump_file(filepath)
    LibRubyParser::PrismString.with(filepath) do |string|
      LibRubyParser.dump_internal(string.source, string.length, filepath)
    end
  end

  # Mirror the Prism.lex API by using the serialization API.
  def self.lex(code, filepath = nil)
    LibRubyParser::PrismBuffer.with do |buffer|
      LibRubyParser.pm_lex_serialize(code, code.bytesize, filepath, buffer.pointer)
      Serialize.load_tokens(Source.new(code), buffer.read)
    end
  end

  # Mirror the Prism.lex_file API by using the serialization API.
  def self.lex_file(filepath)
    LibRubyParser::PrismString.with(filepath) do |string|
      lex(string.read, filepath)
    end
  end

  # Mirror the Prism.parse API by using the serialization API.
  def self.parse(code, filepath = nil)
    Prism.load(code, dump(code, filepath))
  end

  # Mirror the Prism.parse_file API by using the serialization API. This uses
  # native strings instead of Ruby strings because it allows us to use mmap when
  # it is available.
  def self.parse_file(filepath)
    LibRubyParser::PrismString.with(filepath) do |string|
      parse(string.read, filepath)
    end
  end

  # Mirror the Prism.parse_lex API by using the serialization API.
  def self.parse_lex(code, filepath = nil)
    LibRubyParser::PrismBuffer.with do |buffer|
      metadata = [filepath.bytesize, filepath.b, 0].pack("LA*L") if filepath
      LibRubyParser.pm_parse_lex_serialize(code, code.bytesize, buffer.pointer, metadata)

      source = Source.new(code)
      loader = Serialize::Loader.new(source, buffer.read)

      tokens = loader.load_tokens
      node, comments, magic_comments, errors, warnings = loader.load_nodes

      tokens.each { |token,| token.value.force_encoding(loader.encoding) }

      ParseResult.new([node, tokens], comments, magic_comments, errors, warnings, source)
    end
  end

  # Mirror the Prism.parse_lex_file API by using the serialization API.
  def self.parse_lex_file(filepath)
    LibRubyParser::PrismString.with(filepath) do |string|
      parse_lex(string.read, filepath)
    end
  end
end
