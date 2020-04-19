$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "ruby/signature"
require "tmpdir"
require 'minitest/reporters'
require "stringio"

Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new]

module TestHelper
  def parse_type(string, variables: Set.new)
    Ruby::Signature::Parser.parse_type(string, variables: variables)
  end

  def parse_method_type(string, variables: Set.new)
    Ruby::Signature::Parser.parse_method_type(string, variables: variables)
  end

  def type_name(string)
    Ruby::Signature::Namespace.parse(string).yield_self do |namespace|
      last = namespace.path.last
      Ruby::Signature::TypeName.new(name: last, namespace: namespace.parent)
    end
  end

  def silence_warnings
    Ruby::Signature.logger.stub :warn, nil do
      yield
    end
  end

  class SignatureManager
    attr_reader :files

    def initialize
      @files = {}

      files[Pathname("builtin.rbs")] = BUILTINS
    end

    def self.new
      instance = super

      if block_given?
        yield instance
      else
        instance
      end
    end

    BUILTINS = <<SIG
class BasicObject
  def __id__: -> Integer

  private
  def initialize: -> void
end

class Object < BasicObject
  include Kernel
 
  public
  def __id__: -> Integer

  private
  def respond_to_missing?: (Symbol, bool) -> bool
end

module Kernel
  private
  def puts: (*untyped) -> nil
  def to_i: -> Integer
end

class Class < Module
end

class Module
end

class String
  include Comparable
  prepend Enumerable[String, void]

  def self.try_convert: (untyped) -> String?
end

class Integer
end

class Symbol
end

module Comparable
end

module Enumerable[A, B]
end
SIG

    def add_file(path, content)
      files[Pathname(path)] = content
    end

    def build
      Dir.mktmpdir do |tmpdir|
        tmppath = Pathname(tmpdir)

        files.each do |path, content|
          absolute_path = tmppath + path
          absolute_path.parent.mkpath
          absolute_path.write(content)
        end

        loader = Ruby::Signature::EnvironmentLoader.new()
        loader.no_builtin!
        loader.add path: tmppath

        env = Ruby::Signature::Environment.new()
        loader.load(env: env)

        yield env
      end
    end
  end

  def assert_write(decls, string)
    writer = Ruby::Signature::Writer.new(out: StringIO.new)
    writer.write(decls)

    assert_equal string, writer.out.string
  end
end

require "minitest/autorun"
