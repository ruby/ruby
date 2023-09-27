# frozen_string_literal: true

module Prism
  # There are many files in prism that are templated to handle every node type,
  # which means the files can end up being quite large. We autoload them to make
  # our require speed faster since consuming libraries are unlikely to use all
  # of these features.
  autoload :BasicVisitor, "prism/visitor"
  autoload :Compiler, "prism/compiler"
  autoload :Debug, "prism/debug"
  autoload :DesugarCompiler, "prism/desugar_compiler"
  autoload :Dispatcher, "prism/dispatcher"
  autoload :DSL, "prism/dsl"
  autoload :LexCompat, "prism/lex_compat"
  autoload :LexRipper, "prism/lex_compat"
  autoload :MutationCompiler, "prism/mutation_compiler"
  autoload :NodeInspector, "prism/node_inspector"
  autoload :RipperCompat, "prism/ripper_compat"
  autoload :Pack, "prism/pack"
  autoload :Pattern, "prism/pattern"
  autoload :Serialize, "prism/serialize"
  autoload :Visitor, "prism/visitor"

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

require_relative "prism/node"
require_relative "prism/node_ext"
require_relative "prism/parse_result"
require_relative "prism/parse_result/comments"
require_relative "prism/parse_result/newlines"

# This is a Ruby implementation of the prism parser. If we're running on CRuby
# and we haven't explicitly set the PRISM_FFI_BACKEND environment variable, then
# it's going to require the built library. Otherwise, it's going to require a
# module that uses FFI to call into the library.
if RUBY_ENGINE == "ruby" and !ENV["PRISM_FFI_BACKEND"]
  require "prism/prism"
else
  require_relative "prism/ffi"
end
