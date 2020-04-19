require "test_helper"

class Ruby::Signature::RbPrototypeTest < Minitest::Test
  RB = Ruby::Signature::Prototype::RB

  include TestHelper

  def test_class_module
    parser = RB.new

    rb = <<-EOR
class Hello
end

class World < Hello
end

module Foo
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
class Hello
end

class World < Hello
end

module Foo
end
    EOF
  end

  def test_defs
    parser = RB.new

    rb = <<-EOR
class Hello
  def hello(a, b = 3, *c, d, e:, f: 3, **g, &h)
  end

  def self.world
    yield
    yield 1, x: 3
    yield 1, 2, x: 3, y: 2
    yield 1, 2, 'hello' => world 
  end

  def kw_req(a:) end
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
class Hello
  def hello: (untyped a, ?::Integer b, *untyped c, untyped d, e: untyped e, ?f: ::Integer f, **untyped g) { () -> untyped } -> nil

  def self.world: () { (untyped, untyped, untyped, x: untyped, y: untyped) -> untyped } -> untyped

  def kw_req: (a: untyped a) -> nil
end
    EOF
  end

  def test_defs_return_type
    parser = RB.new

    rb = <<-'EOR'
class Hello
  def str() "foo\nbar" end
  def str_lit() "foo" end
  def dstr() "f#{x}oo" end
  def xstr() `ls` end

  def sym() :foo end
  def dsym() :"foo#{bar}" end

  def regx() /foo/ end
  def dregx() /foo#{bar}/ end

  def t() true end
  def f() false end
  def n() nil end
  def n2() end

  def int() 42 end
  def float() 4.2 end
  def complex() 42i end
  def rational() 42r end

  def zlist() [] end
  def list1() [1, '2', :x] end
  def list2() [1, 2, foo] end

  def range1() 1..foo end
  def range2() 1..42 end
  def range3() foo..bar end

  def hash1() {} end
  def hash2() { foo: 1 } end
  def hash3() { foo: { bar: 42 }, x: { y: z } } end
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
class Hello
  def str: () -> ::String

  def str_lit: () -> "foo"

  def dstr: () -> ::String

  def xstr: () -> ::String

  def sym: () -> :foo

  def dsym: () -> ::Symbol

  def regx: () -> ::Regexp

  def dregx: () -> ::Regexp

  def t: () -> ::TrueClass

  def f: () -> ::FalseClass

  def n: () -> nil

  def n2: () -> nil

  def int: () -> 42

  def float: () -> ::Float

  def complex: () -> ::Complex

  def rational: () -> ::Rational

  def zlist: () -> ::Array[untyped]

  def list1: () -> ::Array[1 | "2" | :x]

  def list2: () -> ::Array[untyped]

  def range1: () -> ::Range[::Integer]

  def range2: () -> ::Range[::Integer]

  def range3: () -> ::Range[untyped]

  def hash1: () -> { }

  def hash2: () -> { foo: 1 }

  def hash3: () -> { foo: { bar: 42 }, x: { y: untyped } }
end
    EOF
  end

  def test_sclass
    parser = RB.new

    rb = <<-EOR
class Hello
  class << self
    def hello() end
  end
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
class Hello
  def self.hello: () -> nil
end
    EOF
  end

  def test_meta_programming
    parser = RB.new

    rb = <<-EOR
class Hello
  include Foo
  extend ::Bar, baz

  attr_reader :x
  attr_accessor :y, :z
  attr_writer foo, :a
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
class Hello
  include Foo

  extend ::Bar

  attr_reader x: untyped

  attr_accessor y: untyped

  attr_accessor z: untyped

  attr_writer a: untyped
end
    EOF
  end

  def test_comments
    parser = RB.new

    rb = <<-EOR
# Comments for class.
# This is a comment.
class Hello
  # Comment for include.
  include Foo

  # Comment to be ignored

  # Comment for extend
  extend ::Bar, baz

  # Comment for hello
  def hello()
  end

  # Comment for world
  def self.world
  end

  # Comment for attr_reader
  attr_reader :x

  # Comment for attr_accessor
  attr_accessor :y, :z

  # Comment for attr_writer
  attr_writer foo, :a
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
# Comments for class.
# This is a comment.
class Hello
  # Comment for include.
  include Foo

  # Comment for extend
  extend ::Bar

  # Comment for hello
  def hello: () -> nil

  # Comment for world
  def self.world: () -> nil

  # Comment for attr_reader
  attr_reader x: untyped

  # Comment for attr_accessor
  attr_accessor y: untyped

  # Comment for attr_accessor
  attr_accessor z: untyped

  # Comment for attr_writer
  attr_writer a: untyped
end
    EOF
  end

  def test_toplevel
    parser = RB.new

    rb = <<-EOR
def hello
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
extension Object (Toplevel)
  def hello: () -> nil
end
    EOF
  end

  def test_const
    parser = RB.new

    rb = <<-EOR
module Foo
  VERSION = '0.1.1'
  ::Hello::World = :foo
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
module Foo
end

Foo::VERSION: ::String

Hello::World: ::Symbol
    EOF
  end

  def test_literal_types
    parser = RB.new

    rb = <<-'EOR'
A = 1
B = 1.0
C = "hello#{21}"
D = :hello
E = nil
F = false
G = [1,2,3]
H = { id: 123 }
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
A: ::Integer

B: ::Float

C: ::String

D: ::Symbol

E: untyped?

F: bool

G: ::Array[untyped]

H: ::Hash[untyped, untyped]
    EOF
  end

  def test_argumentless_fcall
    parser = RB.new

    rb = <<-'EOR'
class C
  included do
    do_something
  end
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
class C
end
    EOF
  end

  def test_method_definition_in_fcall
    parser = RB.new

    rb = <<-'EOR'
class C
  private def foo
  end
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
class C
  def foo: () -> nil
end
    EOF
  end

  def test_multiple_nested_class
    parser = RB.new

    rb = <<-'EOR'
module Foo
  class Bar
  end
end

module Foo
  class Baz
  end
end
    EOR

    parser.parse(rb)

    assert_write parser.decls, <<-EOF
module Foo
end

class Foo::Bar
end

class Foo::Baz
end
    EOF
  end
end
