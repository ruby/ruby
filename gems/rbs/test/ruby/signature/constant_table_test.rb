require "test_helper"

class Ruby::Signature::ConstantTableTest < Minitest::Test
  include TestHelper

  ConstantTable = Ruby::Signature::ConstantTable
  Constant = Ruby::Signature::Constant
  TypeName = Ruby::Signature::TypeName
  Namespace = Ruby::Signature::Namespace
  DefinitionBuilder = Ruby::Signature::DefinitionBuilder

  def test_name_to_constant
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
Name: String
EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        table = ConstantTable.new(builder: builder)

        table.name_to_constant(TypeName.new(name: :Object, namespace: Namespace.root)).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Object", constant.name.to_s
          assert_equal "singleton(::Object)", constant.type.to_s
        end

        table.name_to_constant(TypeName.new(name: :Name, namespace: Namespace.root)).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Name", constant.name.to_s
          assert_equal "::String", constant.type.to_s
        end
      end
    end
  end

  def test_reference_top_level
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
Name: String
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        table = ConstantTable.new(builder: builder)

        table.resolve_constant_reference(TypeName.new(name: :Name, namespace: Namespace.empty), context: nil).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Name", constant.name.to_s
          assert_equal "::String", constant.type.to_s
        end

        table.resolve_constant_reference(TypeName.new(name: :ABC, namespace: Namespace.empty), context: nil).tap do |constant|
          assert_nil constant
        end
      end
    end
  end

  def test_reference_constant_context
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
end

Name: "::Name"
Foo::Name: "Foo::Name"
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        table = ConstantTable.new(builder: builder)
        context = Namespace.parse("::Foo")

        table.resolve_constant_reference(TypeName.new(name: :Name, namespace: Namespace.empty), context: context).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Foo::Name", constant.name.to_s
          assert_equal '"Foo::Name"', constant.type.to_s
        end

        table.resolve_constant_reference(TypeName.new(name: :Name, namespace: Namespace.root), context: context).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Name", constant.name.to_s
          assert_equal '"::Name"', constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_inherit
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Parent
end

Parent::MAX: 10000

class Child < Parent
  include Mix
end

module Mix
end

Mix::MIN: 0
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        table = ConstantTable.new(builder: builder)

        table.resolve_constant_reference(TypeName.new(name: :MAX, namespace: Namespace.empty), context: Namespace.parse("::Child")).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Parent::MAX", constant.name.to_s
          assert_equal "10000", constant.type.to_s
        end

        table.resolve_constant_reference(TypeName.new(name: :MIN, namespace: Namespace.empty), context: Namespace.parse("::Child")).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Mix::MIN", constant.name.to_s
          assert_equal '0', constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_inherit_module
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Set
end

module Baz
end
Baz::X: Integer

module Foo::Bar
  include Baz
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        table = ConstantTable.new(builder: builder)

        table.resolve_constant_reference(TypeName.new(name: :Set, namespace: Namespace.empty), context: Namespace.parse("::Foo::Bar")).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Set", constant.name.to_s
          assert_equal 'singleton(::Set)', constant.type.to_s
        end

        table.resolve_constant_reference(TypeName.new(name: :X, namespace: Namespace.empty), context: Namespace.parse("::Foo::Bar")).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Baz::X", constant.name.to_s
          assert_equal '::Integer', constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_inherit2
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
end

Foo::Name: "Foo::Name"
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        table = ConstantTable.new(builder: builder)

        table.resolve_constant_reference(TypeName.new(name: :Name, namespace: Namespace.parse("Foo")), context: Namespace.parse("::Foo")).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Foo::Name", constant.name.to_s
          assert_equal '"Foo::Name"', constant.type.to_s
        end
      end
    end
  end

  def test_reference_constant_inherit3
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Stuff
end

ONE: 1
Object::TWO: 2
Kernel::THREE: 3
BasicObject::FOUR: 4
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        table = ConstantTable.new(builder: builder)

        table.resolve_constant_reference(TypeName.new(name: :ONE, namespace: Namespace.parse("Stuff")), context: nil).tap do |constant|
          assert_nil constant
        end

        table.resolve_constant_reference(TypeName.new(name: :TWO, namespace: Namespace.parse("Stuff")), context: nil).tap do |constant|
          assert_nil constant
        end

        table.resolve_constant_reference(TypeName.new(name: :THREE, namespace: Namespace.parse("Stuff")), context: nil).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::Kernel::THREE", constant.name.to_s
          assert_equal "3", constant.type.to_s
        end

        table.resolve_constant_reference(TypeName.new(name: :FOUR, namespace: Namespace.parse("Stuff")), context: nil).tap do |constant|
          assert_instance_of Constant, constant
          assert_equal "::BasicObject::FOUR", constant.name.to_s
          assert_equal "4", constant.type.to_s
        end
      end
    end
  end

  def test_split_name
    SignatureManager.new do |manager|
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        table = ConstantTable.new(builder: builder)

        assert_equal [:Name], table.split_name(TypeName.new(name: :Name, namespace: Namespace.empty))
        assert_equal [:X, :Y], table.split_name(TypeName.new(name: :Y, namespace: Namespace.parse("X")))
        assert_equal [:X, :Y, :Z], table.split_name(TypeName.new(name: :Z, namespace: Namespace.parse("X::Y")))
      end
    end
  end
end
