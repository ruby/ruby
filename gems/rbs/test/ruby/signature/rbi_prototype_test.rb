require "test_helper"

class Ruby::Signature::RbiPrototypeTest < Minitest::Test
  RBI = Ruby::Signature::Prototype::RBI

  include TestHelper

  def test_1
    parser = RBI.new

    rbi = <<-EOR
class Array < Object
  include Enumerable

  extend T::Generic
  Elem = type_member(:out)

  sig do
    type_parameters(:U).params(
        arg0: T.type_parameter(:U),
        foo: String,
        bar: Integer,
        baz: Object,
        blk: T.proc.params(arg0: Elem).returns(BasicObject)
    )
    .returns(T::Array[T.type_parameter(:U)])
  end
  def self.[](*arg0, foo:, bar: 1, **baz, &blk); end
end
    EOR

    parser.parse(rbi)

    parser.decls

    # decls = parser.decls
    # pp parser.decls
  end

  def test_module
    parser = RBI.new

    rbi = <<-EOR
module Foo
end
EOR

    parser.parse(rbi)

    assert_write parser.decls, <<-EOF
module Foo
end
    EOF
  end

  def test_nested_module
    parser = RBI.new

    rbi = <<-EOR
module Foo
  module Bar
  end
end
    EOR

    parser.parse(rbi)

    assert_write parser.decls, <<-EOF
module Foo
end

module Foo::Bar
end
    EOF
  end

  def test_nested_module2
    parser = RBI.new

    rbi = <<-EOR
module Foo
  module ::Bar
  end
end
    EOR

    parser.parse(rbi)

    assert_write parser.decls, <<-EOF
module Foo
end

module Bar
end
    EOF
  end

  def test_constant
    parser = RBI.new

    rbi = <<-EOR
module Foo
  ABBR_DAYNAMES = T.let(T.unsafe(nil), Array)
  ABBR_MONTHNAMES = T.let(T.unsafe(nil), Integer)
end
    EOR

    parser.parse(rbi)

    assert_write parser.decls, <<-EOF
module Foo
end

Foo::ABBR_DAYNAMES: Array

Foo::ABBR_MONTHNAMES: Integer
    EOF
  end

  def test_alias
    parser = RBI.new

    rbi = <<-EOR
module Foo
  alias_method(:foo, :Bar)
  alias hello world
end
    EOR

    parser.parse(rbi)

    assert_write parser.decls, <<-EOF
module Foo
  alias foo Bar

  alias hello world
end
    EOF
  end

  def test_block_args
    parser = RBI.new

    rbi = <<-EOR
class Hello
  sig do
    type_parameters(:U).params(
        arg0: T.type_parameter(:U),
        blk: T.proc.params(arg0: Elem).returns(BasicObject)
    )
    .returns(T::Array[T.type_parameter(:U)])
  end
  def hello(arg0, &blk); end
end
    EOR

    parser.parse(rbi)

    assert_write parser.decls, <<-EOF
class Hello
  def hello: [U] (U arg0) { (Elem arg0) -> untyped } -> ::Array[U]
end
    EOF
  end

  def test_untyped_block
    parser = RBI.new

    parser.parse(<<-EOF)
class File
  sig { params(blk: T.untyped).void }
  def self.split(&blk); end
end
    EOF

    assert_write parser.decls, <<-EOF
class File
  def self.split: () { () -> untyped } -> void
end
    EOF
  end

  def test_optional_block
    parser = RBI.new

    parser.parse(<<-EOF)
class File
  sig { params(blk: T.nilable(T.proc.void)).void }
  def self.split(&blk); end
end
    EOF

    assert_write parser.decls, <<-EOF
class File
  def self.split: () ?{ () -> void } -> void
end
    EOF
  end

  def test_overloading
    parser = RBI.new

    parser.parse(<<-EOF)
class Class
  sig {void}
  sig do
    params(
        superclass: Class,
    )
    .void
  end
  sig do
    params(
        blk: T.proc.params(arg0: Class).returns(BasicObject),
    )
    .void
  end
  sig do
    params(
        superclass: Class,
        blk: T.proc.params(arg0: Class).returns(BasicObject),
    )
    .void
  end
  def initialize(superclass=_, &blk); end
end
    EOF

    # Maybe, the argument `superclass` does not look like an optional parameter, but cannot detect if it is required or optional.
    assert_write parser.decls, <<-EOF
class Class
  def initialize: () -> void
                | (?Class superclass) -> void
                | () { (Class arg0) -> untyped } -> void
                | (?Class superclass) { (Class arg0) -> untyped } -> void
end
    EOF
  end

  def test_tuple
    parser = RBI.new

    parser.parse(<<-EOF)
class File
  sig do
    params(
        file: String,
    )
    .returns([String, String])
  end
  def self.split(file); end
end
    EOF

    assert_write parser.decls, <<-EOF
class File
  def self.split: (String file) -> [ String, String ]
end
    EOF
  end

  def test_all
    parser = RBI.new

    parser.parse(<<-EOF)
class File
  sig do
    params(
        file: T.all(String, Integer),
    )
    .void
  end
  def self.split(file); end
end
    EOF

    assert_write parser.decls, <<-EOF
class File
  def self.split: (String & Integer file) -> void
end
    EOF
  end

  def test_self_type
    parser = RBI.new

    parser.parse(<<-EOF)
class File
  sig { returns(T.self_type) }
  def self.split; end
end
    EOF

    assert_write parser.decls, <<-EOF
class File
  def self.split: () -> self
end
    EOF
  end

  def test_attached_class
    parser = RBI.new

    parser.parse(<<-EOF)
class File
  sig { returns(T.attached_class) }
  def self.split; end
end
    EOF

    assert_write parser.decls, <<-EOF
class File
  def self.split: () -> instance
end
    EOF
  end

  def test_noreturn
    parser = RBI.new

    parser.parse(<<-EOF)
class File
  sig do
    params(
        file: T.all(String, Integer),
    )
    .returns(T.noreturn)
  end
  def self.split(file); end
end
    EOF

    assert_write parser.decls, <<-EOF
class File
  def self.split: (String & Integer file) -> bot
end
    EOF
  end

  def test_class_of
    parser = RBI.new

    parser.parse(<<-EOF)
class Foo
  sig do
    returns(T.class_of(String))
  end
  def foo; end
end
    EOF

    assert_write parser.decls, <<-EOF
class Foo
  def foo: () -> singleton(String)
end
    EOF
  end

  def test_parameter
    parser = RBI.new

    parser.parse <<-EOF
class Array
  include Enumerable

  extend T::Generic
  Elem = type_member(:out)
end
    EOF

    assert_write parser.decls, <<-EOF
class Array[out Elem]
  include Enumerable
end
    EOF
  end

  def test_basic_object
    parser = RBI.new

    parser.parse <<-EOF
class Foo
  sig { returns(BasicObject) }
  def hello; end
end
    EOF

    assert_write parser.decls, <<-EOF
class Foo
  def hello: () -> untyped
end
    EOF
  end

  def test_bool
    parser = RBI.new

    parser.parse <<-EOF
class Foo
  sig { returns(T::Boolean) }
  def hello; end
end
    EOF

    assert_write parser.decls, <<-EOF
class Foo
  def hello: () -> bool
end
    EOF
  end

  def test_comment
    parser = RBI.new

    parser.parse <<-EOF
# This is a class.
#
#   It is super useful.
class Foo
  # This is useful method.
  sig { void }
  # Another comment.
  sig { returns(Integer) }
  def foo; end
end

# This is a module
module Bar

  # This is singleton method.
  sig { void }
  def self.foo; end
end
    EOF

    assert_write parser.decls, <<-EOF
# This is a class.
#
#   It is super useful.
class Foo
  # This is useful method.
  #
  # Another comment.
  def foo: () -> void
         | () -> Integer
end

# This is a module
module Bar
  # This is singleton method.
  def self.foo: () -> void
end
    EOF
  end

  def test_non_parameter_type_member
    parser = RBI.new

    parser.parse <<-EOF
class Dir
  extend T::Generic

  Elem = type_member(:out, fixed: String)
  include Enumerable
end
    EOF

    assert_write parser.decls, <<-EOF
class Dir
  include Enumerable
end
    EOF
  end

  def test_parameter_type_member_variance
    parser = RBI.new

    parser.parse <<-EOF
class Dir
  extend T::Generic

  X = type_member(:out)
  Y = type_member(:in)
  Z = type_member()

  include Enumerable
end
    EOF

    assert_write parser.decls, <<-EOF
class Dir[out X, in Y, Z]
  include Enumerable
end
    EOF
  end
end
