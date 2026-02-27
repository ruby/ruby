# frozen_string_literal: true
# :markup: markdown
#--
# rbs_inline: enabled

# The Prism Ruby parser.
#
# "Parsing Ruby is suddenly manageable!"
#   - You, hopefully
#
module Prism
  # There are many files in prism that are templated to handle every node type,
  # which means the files can end up being quite large. We autoload them to make
  # our require speed faster since consuming libraries are unlikely to use all
  # of these features.

  autoload :BasicVisitor, "prism/visitor"
  autoload :Compiler, "prism/compiler"
  autoload :DesugarCompiler, "prism/desugar_compiler"
  autoload :Dispatcher, "prism/dispatcher"
  autoload :DotVisitor, "prism/dot_visitor"
  autoload :DSL, "prism/dsl"
  autoload :InspectVisitor, "prism/inspect_visitor"
  autoload :LexCompat, "prism/lex_compat"
  autoload :MutationCompiler, "prism/mutation_compiler"
  autoload :Pattern, "prism/pattern"
  autoload :Reflection, "prism/reflection"
  autoload :Relocation, "prism/relocation"
  autoload :Serialize, "prism/serialize"
  autoload :StringQuery, "prism/string_query"
  autoload :Translation, "prism/translation"
  autoload :Visitor, "prism/visitor"

  # Some of these constants are not meant to be exposed, so marking them as
  # private here.

  private_constant :LexCompat

  # Raised when requested to parse as the currently running Ruby version but Prism has no support for it.
  class CurrentVersionError < ArgumentError
    # Initialize a new exception for the given ruby version string.
    #--
    #: (String version) -> void
    def initialize(version)
      message = +"invalid version: Requested to parse as `version: 'current'`; "
      major, minor, =
        if version.match?(/\A\d+\.\d+.\d+\z/)
          version.split(".").map(&:to_i)
        end

      if major && minor && ((major < 3) || (major == 3 && minor < 3))
        message << " #{version} is below the minimum supported syntax."
      else
        message << " #{version} is unknown. Please update the `prism` gem."
      end

      super(message)
    end
  end

  # :call-seq:
  #   lex_compat(source, **options) -> LexCompat::Result
  #
  # Returns a parse result whose value is an array of tokens that closely
  # resembles the return value of Ripper.lex.
  #
  # For supported options, see Prism.parse.
  #--
  #: (String source, **untyped options) -> LexCompat::Result
  def self.lex_compat(source, **options)
    LexCompat.new(source, **options).result # steep:ignore
  end

  # :call-seq:
  #   load(source, serialized, freeze) -> ParseResult
  #
  # Load the serialized AST using the source as a reference into a tree.
  #--
  #: (String source, String serialized, ?bool freeze) -> ParseResult
  def self.load(source, serialized, freeze = false)
    Serialize.load_parse(source, serialized, freeze)
  end

  # @rbs!
  #    VERSION: String
  #    BACKEND: :CEXT | :FFI
  #
  #    interface _Stream
  #      def gets: (?Integer integer) -> (String | nil)
  #    end
  #
  #    def self.parse:               (String source,  ?filepath: String, ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> ParseResult
  #    def self.profile:             (String source,  ?filepath: String, ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> void
  #    def self.lex:                 (String source,  ?filepath: String, ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> LexResult
  #    def self.parse_lex:           (String source,  ?filepath: String, ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> ParseLexResult
  #    def self.dump:                (String source,  ?filepath: String, ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> String
  #    def self.parse_comments:      (String source,  ?filepath: String, ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> Array[Comment]
  #    def self.parse_success?:      (String source,  ?filepath: String, ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> bool
  #    def self.parse_failure?:      (String source,  ?filepath: String, ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> bool
  #    def self.parse_stream:        (_Stream stream, ?filepath: String, ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> ParseResult
  #    def self.parse_file:          (String filepath,                   ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> ParseResult
  #    def self.profile_file:        (String filepath,                   ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> void
  #    def self.lex_file:            (String filepath,                   ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> LexResult
  #    def self.parse_lex_file:      (String filepath,                   ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> ParseLexResult
  #    def self.dump_file:           (String filepath,                   ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> String
  #    def self.parse_file_comments: (String filepath,                   ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> Array[Comment]
  #    def self.parse_file_success?: (String filepath,                   ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> bool
  #    def self.parse_file_failure?: (String filepath,                   ?command_line: String, ?encoding: Encoding | false, ?freeze: bool, ?frozen_string_literal: bool, ?line: Integer, ?main_script: bool, ?partial_script: bool, ?scopes: Array[Array[Symbol]], ?version: String) -> bool
end

require_relative "prism/polyfill/byteindex"
require_relative "prism/polyfill/warn"
require_relative "prism/node"
require_relative "prism/node_ext"
require_relative "prism/parse_result"

# This is a Ruby implementation of the prism parser. If we're running on CRuby
# and we haven't explicitly set the PRISM_FFI_BACKEND environment variable, then
# it's going to require the built library. Otherwise, it's going to require a
# module that uses FFI to call into the library.
if RUBY_ENGINE == "ruby" and !ENV["PRISM_FFI_BACKEND"]
  # The C extension is the default backend on CRuby.
  Prism::BACKEND = :CEXT

  require "prism/prism"
else
  # The FFI backend is used on other Ruby implementations.
  Prism::BACKEND = :FFI

  require_relative "prism/ffi"
end
