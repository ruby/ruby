require "test_helper"

class Ruby::Signature::WriterTest < Minitest::Test
  include TestHelper

  Parser = Ruby::Signature::Parser
  Writer = Ruby::Signature::Writer

  def format(sig)
    Parser.parse_signature(sig).then do |decls|
      writer = Writer.new(out: StringIO.new)
      writer.write(decls)

      writer.out.string
    end
  end

  def assert_writer(sig)
    assert_equal sig, format(sig)
  end

  def test_const_decl
    assert_writer <<-SIG
# World to world.
# This is a ruby code?
Hello::World: Integer
    SIG
  end

  def test_global_decl
    assert_writer <<-SIG
$name: String
    SIG
  end

  def test_alias_decl
    assert_writer <<-SIG
type ::Module::foo = String | Integer
    SIG
  end

  def test_class_decl
    assert_writer <<-SIG
class Foo::Bar[X] < Array[String]
  %a{This is enumerable}
  include Enumerable[Integer, void]

  extend _World

  prepend Hello

  attr_accessor name: String

  attr_reader age(): Integer

  attr_writer email(@foo): String?

  public

  private

  alias self.id self.identifier

  alias to_s to_str

  @alias: Foo

  self.@hello: "world"

  @@size: 100

  def to_s: () -> String
          | (padding: Integer) -> String

  def self.hello: () -> Integer

  def self?.world: () -> :sym
end
    SIG
  end

  def test_module_decl
    assert_writer <<-SIG
module X : Foo
end
    SIG
  end

  def test_interface_decl
    assert_writer <<-SIG
interface _Each[X, Y]
  def each: () { (X) -> void } -> Y
end
    SIG
  end

  def test_extension_decl
    assert_writer <<-SIG
extension Each[X, Y] (Foo)
end
    SIG
  end

  def test_escape
    assert_writer <<-SIG
interface _Each[X, Y]
  def []: () -> void

  def []=: () -> void

  def !: () -> void

  def __id__: () -> Integer

  def `def`: () -> Symbol

  def timeout: () -> Integer

  def `: (String) -> untyped
end
    SIG
  end

  def test_attributes
    assert_writer <<-SIG
class Foo
  def initialize: () -> void

  incompatible def foo: () -> String
                      | () -> nil
end

class Bar
  def self.new: (String) -> Bar
end
    SIG
  end

  def test_variance
    assert_writer <<-SIG
class Foo[out A, unchecked B, in C] < Bar[A, C, B]
end
    SIG
  end

  def test_preserve_empty_line
    assert_writer <<-SIG
class Foo
  def initialize: () -> void
  def foo: () -> void

  def bar: () -> void
  # comment
  def self.foo: () -> void

  # comment
  def baz: () -> void
end
module Bar
end

class OneEmptyLine
end

# comment
class C
end
# comment
class D
end
    SIG
  end

  def test_remove_double_empty_lines
    src = <<-SIG
class Foo

  def foo: () -> void


  def bar: () -> void
end


module Bar


  def foo: () -> void
end
    SIG

    expected = <<-SIG
class Foo
  def foo: () -> void

  def bar: () -> void
end

module Bar
  def foo: () -> void
end
    SIG

    assert_equal expected, format(src)

  end

  def test_smoke
    Pathname.glob('stdlib/**/*.rbs').each do |path|
      orig_decls = Ruby::Signature::Parser.parse_signature(path.read)

      io = StringIO.new
      w = Ruby::Signature::Writer.new(out: io)
      w.write(orig_decls)
      decls = Ruby::Signature::Parser.parse_signature(io.string)

      assert_equal orig_decls, decls
    end
  end
end
