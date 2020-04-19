require "test_helper"

class Ruby::Signature::DefinitionBuilderTest < Minitest::Test
  include TestHelper

  Environment = Ruby::Signature::Environment
  EnvironmentLoader = Ruby::Signature::EnvironmentLoader
  Declarations = Ruby::Signature::AST::Declarations
  TypeName = Ruby::Signature::TypeName
  Namespace = Ruby::Signature::Namespace
  DefinitionBuilder = Ruby::Signature::DefinitionBuilder
  Definition = Ruby::Signature::Definition
  BuiltinNames = Ruby::Signature::BuiltinNames
  Types = Ruby::Signature::Types
  InvalidTypeApplicationError = Ruby::Signature::InvalidTypeApplicationError
  UnknownMethodAliasError = Ruby::Signature::UnknownMethodAliasError
  InvalidVarianceAnnotationError = Ruby::Signature::InvalidVarianceAnnotationError

  def assert_method_definition(method, types, accessibility: nil)
    assert_instance_of Definition::Method, method
    assert_equal types, method.method_types.map(&:to_s)
    assert_equal accessibility, method.accessibility if accessibility
    yield method.super if block_given?
  end

  def assert_ivar_definitioin(ivar, type)
    assert_instance_of Definition::Variable, ivar
    assert_equal parse_type(type), ivar.type
  end

  def test_build_ancestors
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
        builder = DefinitionBuilder.new(env: env)

        builder.build_ancestors(Definition::Ancestor::Instance.new(name: BuiltinNames::BasicObject.name, args: [])).yield_self do |ancestors|
          assert_equal [Definition::Ancestor::Instance.new(name: BuiltinNames::BasicObject.name, args: [])], ancestors
        end

        builder.build_ancestors(Definition::Ancestor::Instance.new(name: BuiltinNames::Object.name, args: [])).yield_self do |ancestors|
          assert_equal [
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Object.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Kernel.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::BasicObject.name, args: []),
                       ], ancestors
        end

        builder.build_ancestors(Definition::Ancestor::Instance.new(name: BuiltinNames::String.name, args: [])).yield_self do |ancestors|
          assert_equal [
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Enumerable.name, args: [parse_type("::String"), parse_type("void")]),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::String.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Comparable.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Object.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Kernel.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::BasicObject.name, args: []),
                       ], ancestors
        end

        builder.build_ancestors(Definition::Ancestor::Singleton.new(name: BuiltinNames::BasicObject.name)).yield_self do |ancestors|
          assert_equal [
                         Definition::Ancestor::Singleton.new(name: BuiltinNames::BasicObject.name),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Class.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Module.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Object.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Kernel.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::BasicObject.name, args: []),
                       ], ancestors
        end

        builder.build_ancestors(Definition::Ancestor::Singleton.new(name: TypeName.new(name: :Foo, namespace: Namespace.root))).yield_self do |ancestors|
          assert_equal [
                         Definition::Ancestor::Singleton.new(name: TypeName.new(name: :Foo, namespace: Namespace.root)),
                         Definition::Ancestor::Instance.new(name: TypeName.new(name: :X, namespace: Namespace.root), args: []),
                         Definition::Ancestor::Singleton.new(name: BuiltinNames::Object.name),
                         Definition::Ancestor::Singleton.new(name: BuiltinNames::BasicObject.name),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Class.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Module.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Object.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Kernel.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::BasicObject.name, args: []),
                       ], ancestors
        end

        builder.build_ancestors(Definition::Ancestor::Instance.new(name: TypeName.new(name: :Bar, namespace: Namespace.root), args: [parse_type("::Integer")])).yield_self do |ancestors|
          assert_equal [
                         Definition::Ancestor::Instance.new(name: TypeName.new(name: :Bar, namespace: Namespace.root), args: [parse_type("::Integer")]),
                         Definition::Ancestor::Instance.new(name: TypeName.new(name: :Y, namespace: Namespace.root), args: [parse_type("::Integer")]),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Object.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Kernel.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::BasicObject.name, args: []),
                       ], ancestors
        end

        builder.build_ancestors(Definition::Ancestor::Singleton.new(name: BuiltinNames::Kernel.name)).yield_self do |ancestors|
          assert_equal [
                         Definition::Ancestor::Singleton.new(name: BuiltinNames::Kernel.name),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Module.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Object.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Kernel.name, args: []),
                         Definition::Ancestor::Instance.new(name: BuiltinNames::BasicObject.name, args: []),
                       ], ancestors
        end

        builder.build_ancestors(Definition::Ancestor::Instance.new(name: BuiltinNames::Kernel.name, args: [])).yield_self do |ancestors|
          assert_equal [
                         Definition::Ancestor::Instance.new(name: BuiltinNames::Kernel.name, args: []),
                       ], ancestors
        end
      end
    end
  end

  def test_build_ancestors_extension
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
module X[A]
end

module Y[A]
end

class Foo[A]
  include X[Integer]
  prepend Y[A]
  extend Y[1]
end

module Z[A]
end

extension Foo[X] (Foo)
  include Z[X]
  prepend Z[String]
  extend Y[2]
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_ancestors(Definition::Ancestor::Instance.new(name: type_name("::Foo"), args: [Types::Variable.build(:A)])).yield_self do |ancestors|
          assert_equal [
                         Definition::Ancestor::Instance.new(name: type_name("::Y"), args: [Types::Variable.build(:A)]),
                         Definition::Ancestor::Instance.new(name: type_name("::Z"), args: [parse_type("::String")]),
                         Definition::Ancestor::ExtensionInstance.new(name: type_name("::Foo"),
                                                                     args: [Types::Variable.build(:A)],
                                                                     extension_name: :Foo),
                         Definition::Ancestor::Instance.new(name: type_name("::Z"), args: [Types::Variable.build(:A)]),
                         Definition::Ancestor::Instance.new(name: type_name("::Foo"), args: [Types::Variable.build(:A)]),
                         Definition::Ancestor::Instance.new(name: type_name("::X"), args: [parse_type("::Integer")]),
                         Definition::Ancestor::Instance.new(name: type_name("::Object"), args: []),
                         Definition::Ancestor::Instance.new(name: type_name("::Kernel"), args: []),
                         Definition::Ancestor::Instance.new(name: type_name("::BasicObject"), args: []),
                       ],
                       ancestors
        end

        builder.build_ancestors(Definition::Ancestor::Singleton.new(name: type_name("::Foo"))).yield_self do |ancestors|
          assert_equal [
                         Definition::Ancestor::ExtensionSingleton.new(name: type_name("::Foo"),
                                                                      extension_name: :Foo),
                         Definition::Ancestor::Instance.new(name: type_name("::Y"), args: [parse_type(2)]),
                         Definition::Ancestor::Singleton.new(name: type_name("::Foo")),
                         Definition::Ancestor::Instance.new(name: type_name("::Y"), args: [parse_type(1)]),
                         Definition::Ancestor::Singleton.new(name: type_name("::Object")),
                         Definition::Ancestor::Singleton.new(name: type_name("::BasicObject")),
                         Definition::Ancestor::Instance.new(name: type_name("::Class"), args: []),
                         Definition::Ancestor::Instance.new(name: type_name("::Module"), args: []),
                         Definition::Ancestor::Instance.new(name: type_name("::Object"), args: []),
                         Definition::Ancestor::Instance.new(name: type_name("::Kernel"), args: []),
                         Definition::Ancestor::Instance.new(name: type_name("::BasicObject"), args: []),
                       ],
                       ancestors
        end
      end
    end
  end

  def test_build_ancestors_cycle
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
module X[A]
  include Y[A]
end

module Y[A]
  include X[Array[A]]
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        assert_raises do
          builder.build_ancestors(Definition::Ancestor::Instance.new(
            name: type_name("::X"),
            args: [parse_type("::Integer")])
          )
        end
      end
    end
  end

  def test_build_invalid_type_application
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
module X[A]
end

class Y[A, B]
end

class A < Y
  
end

class B < Y[Integer, void]
  include X
end

class C
  extend X
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        assert_raises InvalidTypeApplicationError do
          builder.build_ancestors(Definition::Ancestor::Instance.new(name: type_name("::A"), args: []))
        end

        assert_raises InvalidTypeApplicationError do
          builder.build_ancestors(Definition::Ancestor::Instance.new(name: type_name("::B"), args: []))
        end

        assert_raises InvalidTypeApplicationError do
          builder.build_ancestors(Definition::Ancestor::Singleton.new(name: type_name("::C")))
        end
      end
    end
  end

  def test_build_interface
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
interface _Foo
  def bar: -> _Foo
  include _Hash
end

interface _Hash
  def hash: -> Integer
  def eql?: (untyped) -> bool
end

interface _Baz
  include _Hash[bool]
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        foo = type_name("::_Foo")
        baz = type_name("::_Baz")

        builder.build_interface(foo).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_equal [:bar, :hash, :eql?].sort, definition.methods.keys.sort

          assert_method_definition definition.methods[:bar], ["() -> ::_Foo"], accessibility: :public
          assert_method_definition definition.methods[:hash], ["() -> ::Integer"], accessibility: :public
          assert_method_definition definition.methods[:eql?], ["(untyped) -> bool"], accessibility: :public
        end

        assert_raises InvalidTypeApplicationError do
          builder.build_interface(baz)
        end
      end
    end
  end

  def test_build_one_instance_methods
    SignatureManager.new do |manager|
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_one_instance(BuiltinNames::Object.name).yield_self do |definition|
          definition.methods[:__id__].yield_self do |method|
            assert_method_definition method, ["() -> ::Integer"], accessibility: :public
          end

          definition.methods[:respond_to_missing?].yield_self do |method|
            assert_method_definition method, ["(::Symbol, bool) -> bool"], accessibility: :private
          end
        end
      end
    end
  end

  def test_build_one_instance_method_variance
    SignatureManager.new do |manager|
      manager.files.merge!(Pathname("foo.rbs") => <<-EOF)
class A[out X, unchecked out Y]
  def foo: () -> X
  def bar: (X) -> void
  def baz: (Y) -> void
end

class B[in X, unchecked in Y]
  def foo: (X) -> void
  def bar: () -> X
  def baz: () -> Y 
end

class C[Z]
  def foo: (Z) -> Z
end
      EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        assert_raises(InvalidVarianceAnnotationError) { builder.build_one_instance(type_name("::A")) }.tap do |error|
          assert_equal [
                         InvalidVarianceAnnotationError::MethodTypeError.new(
                           method_name: :bar,
                           method_type: parse_method_type("(X) -> void", variables: [:X]),
                           param: Declarations::ModuleTypeParams::TypeParam.new(name: :X, variance: :covariant, skip_validation: false)
                         )
                       ], error.errors
        end
        assert_raises(InvalidVarianceAnnotationError) { builder.build_one_instance(type_name("::B")) }.tap do|error|
          assert_equal [
                         InvalidVarianceAnnotationError::MethodTypeError.new(
                           method_name: :bar,
                           method_type: parse_method_type("() -> X", variables: [:X]),
                           param: Declarations::ModuleTypeParams::TypeParam.new(name: :X, variance: :contravariant, skip_validation: false)
                         )
                       ], error.errors
        end
        builder.build_one_instance(type_name("::C"))
      end
    end
  end

  def test_build_one_instance_inheritance
    SignatureManager.new do |manager|
      manager.files.merge!(Pathname("foo.rbs") => <<-EOF)
class Base[out X]
end

class A[out X] < Base[X]
end

class B[in X] < Base[X]
end

class C[X] < Base[X]
end
      EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_one_instance(type_name("::A"))
        builder.build_one_instance(type_name("::C"))

        assert_raises(InvalidVarianceAnnotationError) { builder.build_one_instance(type_name("::B")) }.tap do|error|
          assert_equal [
                         InvalidVarianceAnnotationError::InheritanceError.new(
                           param: Declarations::ModuleTypeParams::TypeParam.new(name: :X, variance: :contravariant, skip_validation: false)
                         )
                       ], error.errors
        end
      end
    end
  end

  def test_build_one_instance_mixin
    SignatureManager.new do |manager|
      manager.files.merge!(Pathname("foo.rbs") => <<-EOF)
module M[out X]
end

class A[out X]
  include M[X]
end

class B[in X]
  include M[X]
end

class C[X]
  include M[X]
end
      EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_one_instance(type_name("::A"))
        builder.build_one_instance(type_name("::C"))

        assert_raises(InvalidVarianceAnnotationError) { builder.build_one_instance(type_name("::B")) }.tap do|error|
          assert_equal [
                         InvalidVarianceAnnotationError::MixinError.new(
                           include_member: ::Object.new.tap {|x| x.define_singleton_method(:==) {|x| true } },
                           param: Declarations::ModuleTypeParams::TypeParam.new(name: :X, variance: :contravariant, skip_validation: false)
                         )
                       ], error.errors
        end
      end
    end
  end

  def test_build_one_extension_instance
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
end

extension Hello (Test)
  def assert_equal: (untyped, untyped) -> void
  def self.setup: () -> void

  @name: String
  self.@email: String
  @@count: Integer

  include _Foo[bool]
end

interface _Foo[X]
  def foo: -> X
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_one_instance(type_name("::Hello"), extension_name: :Test).yield_self do |definition|
          assert_equal [:assert_equal, :foo].sort, definition.methods.keys.sort

          definition.methods[:assert_equal].tap do |method|
            assert_method_definition method, ["(untyped, untyped) -> void"], accessibility: :public
          end

          definition.methods[:foo].tap do |method|
            assert_method_definition method, ["() -> bool"], accessibility: :public
          end

          assert_equal [:@name].sort, definition.instance_variables.keys.sort
          definition.instance_variables[:@name].tap do |variable|
            assert_equal parse_type("::String"), variable.type
          end

          assert_equal [:@@count].sort, definition.class_variables.keys.sort
          definition.class_variables[:@@count].tap do |variable|
            assert_equal parse_type("::Integer"), variable.type
          end
        end
      end
    end
  end

  def test_build_one_instance_extension_method_variance
    SignatureManager.new do |manager|
      manager.files.merge!(Pathname("foo.rbs") => <<-EOF)
class A[in X, out Y]
  def foo: (Y) -> X
end

extension A[A, B] (Foo)
  def bar: (A) -> B
  def baz: (B) -> A
end
      EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        assert_raises(Ruby::Signature::InvalidVarianceAnnotationError) { builder.build_one_instance(type_name("::A"), extension_name: :Foo) }.tap do |error|
          assert_equal [
                         Ruby::Signature::InvalidVarianceAnnotationError::MethodTypeError.new(
                           method_name: :baz,
                           method_type: parse_method_type("(B) -> A", variables: [:A, :B]),
                           param: Declarations::ModuleTypeParams::TypeParam.new(name: :A, variance: :contravariant, skip_validation: false)
                         ),
                         Ruby::Signature::InvalidVarianceAnnotationError::MethodTypeError.new(
                           method_name: :baz,
                           method_type: parse_method_type("(B) -> A", variables: [:A, :B]),
                           param: Declarations::ModuleTypeParams::TypeParam.new(name: :B, variance: :covariant, skip_validation: false)
                         )
                       ],
                       error.errors
        end
      end
    end
  end

  def test_build_one_extension_singleton
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
end

extension Hello (Test)
  def assert_equal: (untyped, untyped) -> void
  def self.setup: () -> void

  @name: String
  self.@email: String
  @@count: Integer

  extend _Foo[bool]
end

interface _Foo[X]
  def foo: -> X
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_one_singleton(type_name("::Hello"), extension_name: :Test).yield_self do |definition|
          assert_equal [:setup, :foo].sort, definition.methods.keys.sort

          definition.methods[:setup].tap do |method|
            assert_method_definition method, ["() -> void"], accessibility: :public
          end

          definition.methods[:foo].tap do |method|
            assert_method_definition method, ["() -> bool"], accessibility: :public
          end

          assert_equal [:@email].sort, definition.instance_variables.keys.sort
          definition.instance_variables[:@email].tap do |variable|
            assert_equal parse_type("::String"), variable.type
          end

          assert_equal [:@@count].sort, definition.class_variables.keys.sort
          definition.class_variables[:@@count].tap do |variable|
            assert_equal parse_type("::Integer"), variable.type
          end
        end
      end
    end
  end

  def test_build_one_instance_variables
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello[A]
  @name: A
  @@count: Integer
  self.@email: String
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_one_instance(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_equal [:@name].sort, definition.instance_variables.keys.sort
          definition.instance_variables[:@name].yield_self do |variable|
            assert_instance_of Definition::Variable, variable
            assert_equal parse_type("A", variables: [:A]), variable.type
          end

          assert_equal [:@@count].sort, definition.class_variables.keys.sort
          definition.class_variables[:@@count].yield_self do |variable|
            assert_instance_of Definition::Variable, variable
            assert_equal parse_type("::Integer"), variable.type
          end
        end
      end
    end
  end

  def test_build_one_singleton_methods
    SignatureManager.new do |manager|
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_one_singleton(BuiltinNames::String.name).yield_self do |definition|
          definition.methods[:try_convert].yield_self do |method|
            assert_method_definition method, ["(untyped) -> ::String?"], accessibility: :public
          end
        end
      end
    end
  end

  def test_build_one_singleton_variables
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello[A]
  @name: A
  @@count: Integer
  self.@email: String
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_one_singleton(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_equal [:@email].sort, definition.instance_variables.keys.sort
          definition.instance_variables[:@email].yield_self do |variable|
            assert_instance_of Definition::Variable, variable
            assert_equal parse_type("::String"), variable.type
          end

          assert_equal [:@@count].sort, definition.class_variables.keys.sort
          definition.class_variables[:@@count].yield_self do |variable|
            assert_instance_of Definition::Variable, variable
            assert_equal parse_type("::Integer"), variable.type
          end
        end
      end
    end
  end

  def test_build_instance
    SignatureManager.new do |manager|
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(BuiltinNames::Object.name).yield_self do |definition|
          assert_equal Set.new([:__id__, :initialize, :puts, :respond_to_missing?, :to_i]), Set.new(definition.methods.keys)

          definition.methods[:__id__].yield_self do |method|
            assert_method_definition method, ["() -> ::Integer"], accessibility: :public
          end

          definition.methods[:initialize].yield_self do |method|
            assert_method_definition method, ["() -> void"], accessibility: :private
          end

          definition.methods[:puts].yield_self do |method|
            assert_method_definition method, ["(*untyped) -> nil"], accessibility: :private
          end

          definition.methods[:respond_to_missing?].yield_self do |method|
            assert_method_definition method, ["(::Symbol, bool) -> bool"], accessibility: :private
          end
        end
      end
    end
  end

  def test_build_instance_variables
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello[A]
  @name: A
  @@email: String
end

class Foo < Hello[String]
end

class Bar < Foo
  @name: String
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(type_name("::Bar")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_equal [:@name].sort, definition.instance_variables.keys.sort
          definition.instance_variables[:@name].yield_self do |variable|
            assert_instance_of Definition::Variable, variable
            assert_equal parse_type("::String"), variable.type
            assert_equal :Bar, variable.declared_in.name.name
            assert_equal :Hello, variable.parent_variable.declared_in.name.name
          end

          assert_equal [:@@email].sort, definition.class_variables.keys.sort
          definition.class_variables[:@@email].yield_self do |variable|
            assert_instance_of Definition::Variable, variable
            assert_equal parse_type("::String"), variable.type
            assert_equal :Hello, variable.declared_in.name.name
          end
        end
      end
    end
  end

  def test_build_singleton
    SignatureManager.new do |manager|
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_singleton(BuiltinNames::BasicObject.name).yield_self do |definition|
          assert_equal ["() -> ::BasicObject"], definition.methods[:new].method_types.map {|x| x.to_s }
        end

        builder.build_singleton(BuiltinNames::String.name).yield_self do |definition|
          assert_equal ["() -> ::String"], definition.methods[:new].method_types.map {|x| x.to_s }
        end
      end
    end
  end

  def test_build_singleton_variables
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
  self.@name: Integer
  @@email: String
end

class Foo < Hello
end

class Bar < Foo
  self.@name: String
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_singleton(type_name("::Bar")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_equal [:@name].sort, definition.instance_variables.keys.sort
          definition.instance_variables[:@name].yield_self do |variable|
            assert_instance_of Definition::Variable, variable
            assert_equal parse_type("::String"), variable.type
            assert_equal :Bar, variable.declared_in.name.name
            assert_equal :Hello, variable.parent_variable.declared_in.name.name
          end

          assert_equal [:@@email].sort, definition.class_variables.keys.sort
          definition.class_variables[:@@email].yield_self do |variable|
            assert_instance_of Definition::Variable, variable
            assert_equal parse_type("::String"), variable.type
            assert_equal :Hello, variable.declared_in.name.name
          end
        end
      end
    end
  end

  def test_build_extension
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
end

extension Hello (Hoge)
  def hoge: -> self
  def self.hoge: -> 1
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(type_name("::Hello")).tap do |definition|
          assert_instance_of Definition, definition
          assert_method_definition definition.methods[:hoge], ["() -> self"]
        end

        builder.build_singleton(type_name("::Hello")).tap do |definition|
          assert_instance_of Definition, definition
          assert_method_definition definition.methods[:hoge], ["() -> 1"]
        end
      end
    end
  end

  def test_build_alias
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
  def foo: (String) -> void
  alias bar foo
end

interface _World
  def hello: () -> bool
  alias world hello
end

class Error
  alias self.xxx self.yyy
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(type_name("::Hello")).tap do |definition|
          assert_instance_of Definition, definition
          assert_method_definition definition.methods[:foo], ["(::String) -> void"]
          assert_method_definition definition.methods[:bar], ["(::String) -> void"]
        end

        builder.build_interface(type_name("::_World")).tap do |definition|
          assert_instance_of Definition, definition
          assert_method_definition definition.methods[:hello], ["() -> bool"]
          assert_method_definition definition.methods[:world], ["() -> bool"]
        end

        assert_raises UnknownMethodAliasError do
          builder.build_singleton(type_name("::Error"))
        end
      end
    end
  end

  def test_build_one_module_instance
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
interface _Each[A, B]
  def each: { (A) -> void } -> B
end

module Enumerable2[X, Y] : _Each[X, Y]
  def count: -> Integer
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(type_name("::Enumerable2")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_equal [:count, :each], definition.methods.keys.sort
          assert_method_definition definition.methods[:count], ["() -> ::Integer"]
          assert_method_definition definition.methods[:each], ["() { (X) -> void } -> Y"]
        end
      end
    end
  end

  def test_build_one_module_singleton
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
interface _Each[A, B]
  def each: { (A) -> void } -> B
end

module Enumerable2[X, Y] : _Each[X, Y]
  def count: -> Integer
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_singleton(type_name("::Enumerable2")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_equal [:__id__, :initialize, :puts, :respond_to_missing?, :to_i], definition.methods.keys.sort
          assert_method_definition definition.methods[:__id__], ["() -> ::Integer"]
          assert_method_definition definition.methods[:initialize], ["() -> void"]
          assert_method_definition definition.methods[:puts], ["(*untyped) -> nil"]
          assert_method_definition definition.methods[:respond_to_missing?], ["(::Symbol, bool) -> bool"]
        end
      end
    end
  end

  def test_attributes
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
  attr_reader instance_reader: String
  attr_writer instance_writer(@writer): Integer
  attr_accessor instance_accessor(): Symbol
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_method_definition definition.methods[:instance_reader], ["() -> ::String"]
          assert_ivar_definitioin definition.instance_variables[:@instance_reader], "::String"

          assert_method_definition definition.methods[:instance_writer=], ["(::Integer instance_writer) -> ::Integer"]
          assert_ivar_definitioin definition.instance_variables[:@writer], "::Integer"

          assert_method_definition definition.methods[:instance_accessor], ["() -> ::Symbol"]
          assert_method_definition definition.methods[:instance_accessor=], ["(::Symbol instance_accessor) -> ::Symbol"]
          assert_nil definition.instance_variables[:@instance_accessor]
        end
      end
    end
  end

  def test_incompatible_method
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
  def initialize: () -> void
  incompatible def hello: () -> Integer
  def world: -> void
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_equal [:incompatible], definition.methods[:initialize].attributes
          assert_equal [:incompatible], definition.methods[:hello].attributes
          assert_equal [], definition.methods[:world].attributes
        end
      end

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_singleton(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_equal [:incompatible], definition.methods[:new].attributes
        end
      end
    end
  end

  def test_initialize
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello[A]
  def initialize: [X] () { (X) -> A } -> void
  def get: () -> A
end
EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_method_definition definition.methods[:initialize], ["[X] () { (X) -> A } -> void"]
        end

        builder.build_singleton(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_method_definition definition.methods[:new], ["[A, X] () { (X) -> A } -> ::Hello[A]"]
        end
      end
    end
  end

  def test_initialize2
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello[A]
  def initialize: [A] () { (A) -> void } -> void
end
EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_method_definition definition.methods[:initialize], ["[A] () { (A) -> void } -> void"]
        end

        builder.build_singleton(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          definition.methods[:new].tap do |method|
            assert_instance_of Definition::Method, method

            assert_equal 1, method.method_types.size
            # [A, A@1] () { (A@1) -> void } -> ::Hello[A]
            assert_match(/\A\[A, A@(\d+)\] \(\) { \(A@\1\) -> void } -> ::Hello\[A\]\Z/, method.method_types[0].to_s)
          end
        end
      end
    end
  end

  def test_build_super
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
  def say: (String) -> void
end

extension Hello (World)
  def say: (Integer) -> void
         | super
end
EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_method_definition definition.methods[:say], ["(::Integer) -> void", "(::String) -> void"]
        end
      end
    end
  end

  def test_build_alias_forward
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
  alias foo bar
  def bar: () -> Integer

  alias self.hoge self.huga
  def self.huga: () -> void
end

interface _Person
  alias first_name name
  def name: () -> String
end
EOF

      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        builder.build_instance(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_method_definition definition.methods[:foo], ["() -> ::Integer"]
        end

        builder.build_singleton(type_name("::Hello")).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_method_definition definition.methods[:hoge], ["() -> void"]
        end

        interface_name = type_name("::_Person")
        builder.build_interface(interface_name).yield_self do |definition|
          assert_instance_of Definition, definition

          assert_method_definition definition.methods[:first_name], ["() -> ::String"]
        end
      end
    end
  end
end
