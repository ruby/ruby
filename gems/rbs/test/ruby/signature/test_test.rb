require "test_helper"

require "ruby/signature/test"
require "logger"

return unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7.0')

class Ruby::Signature::TestTest < Minitest::Test
  include TestHelper

  DefinitionBuilder = Ruby::Signature::DefinitionBuilder
  Test = Ruby::Signature::Test

  def io
    @io ||= StringIO.new
  end

  def logger
    @logger ||= Logger.new(io).tap do |l|
      l.level = "debug"
    end
  end

  def test_verify_instance_method
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
module X
end

class Foo
  extend X
end

module Y[A]
end

class Bar[X]
  include Y[X]
end
EOF
      manager.build do |env|
        klass = Class.new do
          def foo(*args)
            if block_given?
              (yield 123).to_s
            else
              :foo
            end
          end

          def self.name
            "Foo"
          end
        end

        hook = Ruby::Signature::Test::Hook.install(env, klass, logger: logger)
                 .verify(instance_method: :foo,
                         types: ["(::String x, ::Integer i, foo: 123 foo) { (Integer) -> Array[Integer] } -> ::String"])

        hook.run do
          instance = klass.new
          instance.foo { 1+2 }
          instance.foo("", 3, foo: 234) {}
          instance.foo
        end
      end
    end
  end

  def test_verify_singleton_method
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
  def self.open: () { (Foo) -> void } -> Foo
end
EOF
      manager.build do |env|
        klass = Class.new do
          def self.open(&block)
            x = new
            instance_exec x, &block
            x
          end

          def self.name
            "Foo"
          end
        end

        hook = Ruby::Signature::Test::Hook.install(env, klass, logger: logger)
                 .verify(singleton_method: :open,
                         types: ["() { (::String) -> void } -> ::String"])

        hook.run do
          _foo = klass.open {|foo|
            1 + 2 + 3
          }
        end

        refute_empty hook.errors
      end
    end
  end

  def test_verify_all
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
  def self.open: () { (String) -> void } -> Integer
  def foo: (*untyped) -> String
end
EOF
      manager.build do |env|
        klass = Class.new do
          def self.open(&block)
            x = new
            x.instance_exec "", &block
            1
          end

          def foo(*args)
            "hello foo"
          end

          def self.name
            "Foo"
          end
        end

        ::Object.const_set :Foo, klass

        hook = Ruby::Signature::Test::Hook.install(env, klass, logger: logger).verify_all

        hook.run do
          _foo = klass.open {
            _bar = 1 + 2 + 3

            self.foo(1, 2, 3)
          }
        end

        assert_empty hook.errors
      ensure
        ::Object.instance_eval do
          remove_const :Foo
        end
      end
    end
  end

  def test_type_check
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Array[Elem]
end

type foo = String | Integer | [String, String] | ::Array[Integer]
type M::t = Integer
type M::s = t

interface _ToInt
  def to_int: () -> Integer
end
EOF
      manager.build do |env|
        typecheck = Ruby::Signature::Test::TypeCheck.new(self_class: Integer, builder: DefinitionBuilder.new(env: env))

        assert typecheck.value(3, parse_type("::foo"))
        assert typecheck.value("3", parse_type("::foo"))
        assert typecheck.value(["foo", "bar"], parse_type("::foo"))
        assert typecheck.value([1, 2, 3], parse_type("::foo"))
        refute typecheck.value(:foo, parse_type("::foo"))
        refute typecheck.value(["foo", 3], parse_type("::foo"))
        refute typecheck.value([1, 2, "3"], parse_type("::foo"))

        assert typecheck.value(Object, parse_type("singleton(::Object)"))
        assert typecheck.value(Object, parse_type("::Class"))
        refute typecheck.value(Object, parse_type("singleton(::String)"))

        assert typecheck.value(3, parse_type("::M::t"))
        assert typecheck.value(3, parse_type("::M::s"))

        assert typecheck.value(3, parse_type("::_ToInt"))
        refute typecheck.value("3", parse_type("::_ToInt"))

        assert typecheck.value([1,2,3].each, parse_type("Enumerator[Integer, Array[Integer]]"))
        assert typecheck.value(loop, parse_type("Enumerator[nil, bot]"))
      end
    end
  end

  def test_typecheck_return
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
type foo = String | Integer
EOF
      manager.build do |env|
        typecheck = Ruby::Signature::Test::TypeCheck.new(self_class: Object, builder: DefinitionBuilder.new(env: env))

        parse_method_type("(Integer) -> String").tap do |method_type|
          errors = []
          typecheck.return "#foo",
                           method_type,
                           method_type.type,
                           Test::ArgumentsReturn.new(arguments: [1], return_value: nil, exception: RuntimeError.new("test")),
                           errors,
                           return_error: Test::Errors::ReturnTypeError
          assert_empty errors

          errors.clear
          typecheck.return "#foo",
                           method_type,
                           method_type.type,
                           Test::ArgumentsReturn.new(arguments: [1], return_value: "5", exception: nil),
                           errors,
                           return_error: Test::Errors::ReturnTypeError
          assert_empty errors
        end

        parse_method_type("(Integer) -> bot").tap do |method_type|
          errors = []
          typecheck.return "#foo",
                           method_type,
                           method_type.type,
                           Test::ArgumentsReturn.new(arguments: [1], return_value: nil, exception: RuntimeError.new("test")),
                           errors,
                           return_error: Test::Errors::ReturnTypeError
          assert_empty errors

          errors.clear
          typecheck.return "#foo",
                           method_type,
                           method_type.type,
                           Test::ArgumentsReturn.new(arguments: [1], return_value: "5", exception: nil),
                           errors,
                           return_error: Test::Errors::ReturnTypeError
          assert errors.any? {|error| error.is_a?(Test::Errors::ReturnTypeError) }
        end
      end
    end
  end

  def test_typecheck_args
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
type foo = String | Integer
EOF
      manager.build do |env|
        typecheck = Ruby::Signature::Test::TypeCheck.new(self_class: Object, builder: DefinitionBuilder.new(env: env))

        parse_method_type("(Integer) -> String").tap do |method_type|
          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(arguments: [1], return_value: "1", exception: nil),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors

          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(arguments: ["1"], return_value: "1", exception: nil),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert errors.any? {|error| error.is_a?(Test::Errors::ArgumentTypeError) }

          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(arguments: [1, 2], return_value: "1", exception: nil),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert errors.any? {|error| error.is_a?(Test::Errors::ArgumentError) }

          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(arguments: [{ hello: :world }], return_value: "1", exception: nil),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert errors.any? {|error| error.is_a?(Test::Errors::ArgumentTypeError) }
        end

        parse_method_type("(foo: Integer, ?bar: String, **Symbol) -> String").tap do |method_type|
          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(
                           arguments: [{ foo: 31, baz: :baz }],
                           return_value: "1",
                           exception: nil
                         ),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors

          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(
                           arguments: [{ foo: "foo" }],
                           return_value: "1",
                           exception: nil
                         ),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert errors.any? {|error| error.is_a?(Test::Errors::ArgumentTypeError) }

          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(
                           arguments: [{ bar: "bar" }],
                           return_value: "1",
                           exception: nil
                         ),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert errors.any? {|error| error.is_a?(Test::Errors::ArgumentError) }
        end

        parse_method_type("(?String, ?encoding: String) -> String").tap do |method_type|
          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(
                           arguments: [{ encoding: "ASCII-8BIT" }],
                           return_value: "foo",
                           exception: nil
                         ),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors
        end

        parse_method_type("(parent: untyped, type: untyped) -> untyped").tap do |method_type|
          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(
                           arguments: [{ parent: nil, type: nil }],
                           return_value: nil,
                           exception: nil
                         ),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors.map {|e| Test::Errors.to_string(e) }
        end

        parse_method_type("(Integer?, *String) -> String").tap do |method_type|
          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(
                           arguments: [1],
                           return_value: "1",
                           exception: nil
                         ),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors

          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(
                           arguments: [1, ''],
                           return_value: "1",
                           exception: nil
                         ),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors

          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.new(
                           arguments: [1, '', ''],
                           return_value: "1",
                           exception: nil
                         ),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors
        end
      end
    end
  end

  def test_verify_block_once
    SignatureManager.new do |manager|
      manager.build do |env|
        klass = Class.new do
          def hello
            yield ["3", 3]
          end

          def world
            yield "3", 3
          end

          def self.name
            "Foo"
          end
        end

        hook = Ruby::Signature::Test::Hook.install(env, klass, logger: logger)
                 .verify(instance_method: :hello,
                         types: ["() { (::String, ::Integer) -> void } -> void"])
                 .verify(instance_method: :world,
                         types: ["() { ([::String, ::Integer]) -> void } -> void"])

        hook.run do
          klass.new.hello { }
          klass.new.world { }
        end

        refute_empty hook.errors.select {|e| e.method_name == "#hello" }.map {|e| Test::Errors.to_string(e) }
        refute_empty hook.errors.select {|e| e.method_name == "#world" }.map {|e| Test::Errors.to_string(e) }
      end
    end
  end

  def test_verify_block_no_yelld
    SignatureManager.new do |manager|
      manager.build do |env|
        klass = Class.new do
          def hello
          end

          def self.name
            "Foo"
          end
        end

        hook = Ruby::Signature::Test::Hook.install(env, klass, logger: logger)
                 .verify(instance_method: :hello,
                         types: ["() { (::String, ::Integer) -> void } -> void"])
        hook.run do
          klass.new.hello { }
        end

        assert_empty hook.errors.map {|e| Test::Errors.to_string(e) }
      end
    end
  end

  def test_verify_block_no_yied
    SignatureManager.new do |manager|
      manager.build do |env|
        klass = Class.new do
          def hello
          end

          def self.name
            "Foo"
          end
        end

        hook = Ruby::Signature::Test::Hook.install(env, klass, logger: logger)
                 .verify(instance_method: :hello,
                         types: ["() { (::String, ::Integer) -> void } -> void"])
        hook.run do
          klass.new.hello { }
        end

        assert_empty hook.errors.map {|e| Test::Errors.to_string(e) }
      end
    end
  end

  def test_verify_block_not_given
    SignatureManager.new do |manager|
      manager.build do |env|
        klass = Class.new do
          def hello
          end

          def self.name
            "Foo"
          end
        end

        hook = Ruby::Signature::Test::Hook.install(env, klass, logger: logger)
                 .verify(instance_method: :hello,
                         types: ["() { (::String, ::Integer) -> void } -> void"])
        hook.run do
          klass.new.hello
        end

        refute_empty hook.errors.map {|e| Test::Errors.to_string(e) }
      end
    end
  end

  def test_verify_block_yielded_twice
    SignatureManager.new do |manager|
      manager.build do |env|
        klass = Class.new do
          def hello
            yield
            yield "foo", 2
          end

          def self.name
            "Foo"
          end
        end

        hook = Ruby::Signature::Test::Hook.install(env, klass, logger: logger)
                 .verify(instance_method: :hello,
                         types: ["() { (::String, ::Integer) -> void } -> void"])
        hook.run do
          klass.new.hello {}
        end

        refute_empty hook.errors.map {|e| Test::Errors.to_string(e) }
      end
    end
  end

  def test_verify_error
    SignatureManager.new do |manager|
      manager.build do |env|
        klass = Class.new do
          def hello()
            yield 30
          end

          def self.name
            "Foo"
          end
        end

        hook = Ruby::Signature::Test::Hook.install(env, klass, logger: logger)
                 .raise_on_error!
                 .verify(instance_method: :hello,
                         types: ["() { (String) -> void } -> void"])


        assert_raises(Ruby::Signature::Test::Hook::Error) do
          hook.run do
            klass.new.hello {|x| 30 }
          end
        end
      end
    end
  end
end
