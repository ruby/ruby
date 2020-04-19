require "test_helper"

class Ruby::Signature::EnvironmentTest < Minitest::Test
  include TestHelper

  Environment = Ruby::Signature::Environment
  Namespace = Ruby::Signature::Namespace
  InvalidTypeApplicationError = Ruby::Signature::InvalidTypeApplicationError

  def test_absolute_type_name
    SignatureManager.new do |manager|
      manager.add_file("foo.rbs", <<-EOF)
class String::Foo
end

class Foo
end
      EOF

      manager.build do |env|
        assert_equal type_name("::Foo"), env.absolute_type_name(type_name("Foo"), namespace: Namespace.root)
        assert_equal type_name("::String::Foo"), env.absolute_type_name(type_name("Foo"), namespace: Namespace.parse("::String"))
        assert_nil env.absolute_type_name(type_name("Bar"), namespace: Namespace.parse("::String")) { nil }
      end
    end
  end

  def test_absolute_type
    SignatureManager.new do |manager|
      manager.add_file("foo.rbs", <<-EOF)
class Array[A]
end

class String::Foo
end

class Foo
end
      EOF

      manager.build do |env|
        assert_equal parse_type("::Foo"), env.absolute_type(parse_type("Foo"), namespace: Namespace.root)
        assert_equal parse_type("::String::Foo"), env.absolute_type(parse_type("Foo"), namespace: Namespace.parse("::String"))

        assert_equal parse_type("singleton(::Foo)"), env.absolute_type(parse_type("singleton(Foo)"), namespace: Namespace.root)
        assert_equal parse_type("singleton(::String::Foo)"), env.absolute_type(parse_type("singleton(Foo)"), namespace: Namespace.parse("::String"))

        assert_equal parse_type("::Array[::Foo]"), env.absolute_type(parse_type("Array[Foo]"), namespace: Namespace.root)
        assert_equal parse_type("::Array[::String::Foo]"), env.absolute_type(parse_type("Array[Foo]"), namespace: Namespace.parse("::String"))

        assert_equal parse_type("::Integer | ::Foo"), env.absolute_type(parse_type("Integer | Foo"), namespace: Namespace.root)
        assert_equal parse_type("::Integer | ::String::Foo"), env.absolute_type(parse_type("Integer | Foo"), namespace: Namespace.parse("::String"))

        assert_equal parse_type("::Integer & ::Foo"), env.absolute_type(parse_type("Integer & Foo"), namespace: Namespace.root)
        assert_equal parse_type("::Integer & ::String::Foo"), env.absolute_type(parse_type("Integer & Foo"), namespace: Namespace.parse("::String"))

        assert_equal parse_type("[::Foo, untyped]"), env.absolute_type(parse_type("[Foo, untyped]"), namespace: Namespace.root)
        assert_equal parse_type("[::String::Foo, untyped]"), env.absolute_type(parse_type("[Foo, untyped]"), namespace: Namespace.parse("::String"))

        assert_equal parse_type("{foo: ::Foo}"), env.absolute_type(parse_type("{ foo: Foo }"), namespace: Namespace.root)
        assert_equal parse_type("{foo: ::String::Foo }"), env.absolute_type(parse_type("{ foo: Foo }"), namespace: Namespace.parse("::String"))

        assert_equal parse_type("::Foo?"), env.absolute_type(parse_type("Foo?"), namespace: Namespace.root)
        assert_equal parse_type("::String::Foo?"), env.absolute_type(parse_type("Foo?"), namespace: Namespace.parse("::String"))

        assert_equal parse_type("^(::Foo) -> ::Foo"), env.absolute_type(parse_type("^(Foo) -> Foo"), namespace: Namespace.root)
        assert_equal parse_type("^(::String::Foo) -> ::String::Foo"), env.absolute_type(parse_type("^(Foo) -> Foo"), namespace: Namespace.parse("::String"))
      end
    end
  end

  def test_validate
    SignatureManager.new do |manager|
      manager.add_file("foo.rbs", <<-EOF)
class Array[A]
end

class String::Foo
end

class Foo
end
      EOF

      manager.build do |env|
        root = Namespace.root

        env.validate(parse_type("::Foo"), namespace: root)
        env.validate(parse_type("::String::Foo"), namespace: root)

        env.validate(parse_type("Array[String]"), namespace: root)
        assert_raises InvalidTypeApplicationError do
          env.validate(parse_type("Array"), namespace: root)
        end
        assert_raises InvalidTypeApplicationError do
          env.validate(parse_type("Array[1,2,3]"), namespace: root)
        end
      end
    end
  end
end
