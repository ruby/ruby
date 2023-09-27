# frozen_string_literal: true

module YARP
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
require_relative "yarp/node_ext"
require_relative "yarp/parse_result"
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
