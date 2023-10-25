require_relative '../spec_helper'
require_relative '../fixtures/constants'
require_relative 'fixtures/constants_sclass'
require_relative 'fixtures/constant_visibility'

# Read the documentation in fixtures/constants.rb for the guidelines and
# rationale for the structure and organization of these specs.

describe "Literal (A::X) constant resolution" do
  describe "with statically assigned constants" do
    it "searches the immediate class or module scope first" do
      ConstantSpecs::ClassA::CS_CONST10.should == :const10_10
      ConstantSpecs::ModuleA::CS_CONST10.should == :const10_1
      ConstantSpecs::ParentA::CS_CONST10.should == :const10_5
      ConstantSpecs::ContainerA::CS_CONST10.should == :const10_2
      ConstantSpecs::ContainerA::ChildA::CS_CONST10.should == :const10_3
    end

    it "searches a module included in the immediate class before the superclass" do
      ConstantSpecs::ContainerA::ChildA::CS_CONST15.should == :const15_1
    end

    it "searches the superclass before a module included in the superclass" do
      ConstantSpecs::ContainerA::ChildA::CS_CONST11.should == :const11_1
    end

    it "searches a module included in the superclass" do
      ConstantSpecs::ContainerA::ChildA::CS_CONST12.should == :const12_1
    end

    it "searches the superclass chain" do
      ConstantSpecs::ContainerA::ChildA::CS_CONST13.should == :const13
    end

    it "searches Object if no class or module qualifier is given" do
      CS_CONST1.should == :const1
      CS_CONST10.should == :const10_1
    end

    it "searches Object after searching other scopes" do
      module ConstantSpecs::SpecAdded1
        CS_CONST10.should == :const10_1
      end
    end

    it "searches Object if a toplevel qualifier (::X) is given" do
      ::CS_CONST1.should == :const1
      ::CS_CONST10.should == :const10_1
    end

    it "does not search the singleton class of the class or module" do
      -> do
        ConstantSpecs::ContainerA::ChildA::CS_CONST14
      end.should raise_error(NameError)
      -> { ConstantSpecs::CS_CONST14 }.should raise_error(NameError)
    end
  end

  describe "with dynamically assigned constants" do
    it "searches the immediate class or module scope first" do
      ConstantSpecs::ClassB::CS_CONST101 = :const101_1
      ConstantSpecs::ClassB::CS_CONST101.should == :const101_1

      ConstantSpecs::ParentB::CS_CONST101 = :const101_2
      ConstantSpecs::ParentB::CS_CONST101.should == :const101_2

      ConstantSpecs::ContainerB::CS_CONST101 = :const101_3
      ConstantSpecs::ContainerB::CS_CONST101.should == :const101_3

      ConstantSpecs::ContainerB::ChildB::CS_CONST101 = :const101_4
      ConstantSpecs::ContainerB::ChildB::CS_CONST101.should == :const101_4

      ConstantSpecs::ModuleA::CS_CONST101 = :const101_5
      ConstantSpecs::ModuleA::CS_CONST101.should == :const101_5
    end

    it "searches a module included in the immediate class before the superclass" do
      ConstantSpecs::ParentB::CS_CONST102 = :const102_1
      ConstantSpecs::ModuleF::CS_CONST102 = :const102_2
      ConstantSpecs::ContainerB::ChildB::CS_CONST102.should == :const102_2
    end

    it "searches the superclass before a module included in the superclass" do
      ConstantSpecs::ModuleE::CS_CONST103 = :const103_1
      ConstantSpecs::ParentB::CS_CONST103 = :const103_2
      ConstantSpecs::ContainerB::ChildB::CS_CONST103.should == :const103_2
    end

    it "searches a module included in the superclass" do
      ConstantSpecs::ModuleA::CS_CONST104 = :const104_1
      ConstantSpecs::ModuleE::CS_CONST104 = :const104_2
      ConstantSpecs::ContainerB::ChildB::CS_CONST104.should == :const104_2
    end

    it "searches the superclass chain" do
      ConstantSpecs::ModuleA::CS_CONST105 = :const105
      ConstantSpecs::ContainerB::ChildB::CS_CONST105.should == :const105
    end

    it "searches Object if no class or module qualifier is given" do
      CS_CONST106 = :const106
      CS_CONST106.should == :const106
    end

    it "searches Object if a toplevel qualifier (::X) is given" do
      ::CS_CONST107 = :const107
      ::CS_CONST107.should == :const107
    end

    it "does not search the singleton class of the class or module" do
      class << ConstantSpecs::ContainerB::ChildB
        CS_CONST108 = :const108_1
      end

      -> do
        ConstantSpecs::ContainerB::ChildB::CS_CONST108
      end.should raise_error(NameError)

      module ConstantSpecs
        class << self
          CS_CONST108 = :const108_2
        end
      end

      -> { ConstantSpecs::CS_CONST108 }.should raise_error(NameError)
    end

    it "returns the updated value when a constant is reassigned" do
      ConstantSpecs::ClassB::CS_CONST109 = :const109_1
      ConstantSpecs::ClassB::CS_CONST109.should == :const109_1

      -> {
        ConstantSpecs::ClassB::CS_CONST109 = :const109_2
      }.should complain(/already initialized constant/)
      ConstantSpecs::ClassB::CS_CONST109.should == :const109_2
    end

    ruby_version_is "3.2" do
      it "evaluates left-to-right" do
        mod = Module.new

        mod.module_eval <<-EOC
          order = []
          ConstantSpecsRHS = Module.new
          (order << :lhs; ConstantSpecsRHS)::B = (order << :rhs)
        EOC

        mod::ConstantSpecsRHS::B.should == [:lhs, :rhs]
      end
    end

    ruby_version_is ""..."3.2" do
      it "evaluates the right hand side before evaluating a constant path" do
        mod = Module.new

        mod.module_eval <<-EOC
          ConstantSpecsRHS::B = begin
            module ConstantSpecsRHS; end

            "hello"
          end
        EOC

        mod::ConstantSpecsRHS::B.should == 'hello'
      end
    end
  end

  it "raises a NameError if no constant is defined in the search path" do
    -> { ConstantSpecs::ParentA::CS_CONSTX }.should raise_error(NameError)
  end

  it "uses the module or class #name to craft the error message" do
    mod = Module.new do
      def self.name
        "ModuleName"
      end

      def self.inspect
        "<unusable info>"
      end
    end

    -> { mod::DOES_NOT_EXIST }.should raise_error(NameError, /uninitialized constant ModuleName::DOES_NOT_EXIST/)
  end

  it "uses the module or class #inspect to craft the error message if they are anonymous" do
    mod = Module.new do
      def self.name
        nil
      end

      def self.inspect
        "<unusable info>"
      end
    end

    -> { mod::DOES_NOT_EXIST }.should raise_error(NameError, /uninitialized constant <unusable info>::DOES_NOT_EXIST/)
  end

  it "sends #const_missing to the original class or module scope" do
    ConstantSpecs::ClassA::CS_CONSTX.should == :CS_CONSTX
  end

  it "evaluates the qualifier" do
    ConstantSpecs.get_const::CS_CONST2.should == :const2
  end

  it "raises a TypeError if a non-class or non-module qualifier is given" do
    -> { CS_CONST1::CS_CONST }.should raise_error(TypeError)
    -> { 1::CS_CONST         }.should raise_error(TypeError)
    -> { "mod"::CS_CONST     }.should raise_error(TypeError)
    -> { false::CS_CONST     }.should raise_error(TypeError)
  end
end

describe "Constant resolution within methods" do
  describe "with statically assigned constants" do
    it "searches the immediate class or module scope first" do
      ConstantSpecs::ClassA.const10.should == :const10_10
      ConstantSpecs::ParentA.const10.should == :const10_5
      ConstantSpecs::ContainerA.const10.should == :const10_2
      ConstantSpecs::ContainerA::ChildA.const10.should == :const10_3

      ConstantSpecs::ClassA.new.const10.should == :const10_10
      ConstantSpecs::ParentA.new.const10.should == :const10_5
      ConstantSpecs::ContainerA::ChildA.new.const10.should == :const10_3
    end

    it "searches a module included in the immediate class before the superclass" do
      ConstantSpecs::ContainerA::ChildA.const15.should == :const15_1
      ConstantSpecs::ContainerA::ChildA.new.const15.should == :const15_1
    end

    it "searches the superclass before a module included in the superclass" do
      ConstantSpecs::ContainerA::ChildA.const11.should == :const11_1
      ConstantSpecs::ContainerA::ChildA.new.const11.should == :const11_1
    end

    it "searches a module included in the superclass" do
      ConstantSpecs::ContainerA::ChildA.const12.should == :const12_1
      ConstantSpecs::ContainerA::ChildA.new.const12.should == :const12_1
    end

    it "searches the superclass chain" do
      ConstantSpecs::ContainerA::ChildA.const13.should == :const13
      ConstantSpecs::ContainerA::ChildA.new.const13.should == :const13
    end

    it "searches the lexical scope of the method not the receiver's immediate class" do
      ConstantSpecs::ContainerA::ChildA.const19.should == :const19_1
    end

    it "searches the lexical scope of a singleton method" do
      ConstantSpecs::CS_CONST18.const17.should == :const17_1
    end

    it "does not search the lexical scope of the caller" do
      -> { ConstantSpecs::ClassA.const16 }.should raise_error(NameError)
    end

    it "searches the lexical scope of a block" do
      ConstantSpecs::ClassA.const22.should == :const22_1
    end

    it "searches Object as a lexical scope only if Object is explicitly opened" do
      ConstantSpecs::ContainerA::ChildA.const20.should == :const20_1
      ConstantSpecs::ContainerA::ChildA.const21.should == :const21_1
    end

    it "does not search the lexical scope of qualifying modules" do
      -> do
        ConstantSpecs::ContainerA::ChildA.const23
      end.should raise_error(NameError)
    end
  end

  describe "with dynamically assigned constants" do
    it "searches the immediate class or module scope first" do
      ConstantSpecs::ModuleA::CS_CONST201 = :const201_1

      class ConstantSpecs::ClassB; CS_CONST201 = :const201_2; end
      ConstantSpecs::ParentB::CS_CONST201 = :const201_3
      ConstantSpecs::ContainerB::CS_CONST201 = :const201_4
      ConstantSpecs::ContainerB::ChildB::CS_CONST201 = :const201_5

      ConstantSpecs::ClassB.const201.should == :const201_2
      ConstantSpecs::ParentB.const201.should == :const201_3
      ConstantSpecs::ContainerB.const201.should == :const201_4
      ConstantSpecs::ContainerB::ChildB.const201.should == :const201_5

      ConstantSpecs::ClassB.new.const201.should == :const201_2
      ConstantSpecs::ParentB.new.const201.should == :const201_3
      ConstantSpecs::ContainerB::ChildB.new.const201.should == :const201_5
    end

    it "searches a module included in the immediate class before the superclass" do
      ConstantSpecs::ParentB::CS_CONST202 = :const202_2
      ConstantSpecs::ContainerB::ChildB::CS_CONST202 = :const202_1

      ConstantSpecs::ContainerB::ChildB.const202.should == :const202_1
      ConstantSpecs::ContainerB::ChildB.new.const202.should == :const202_1
    end

    it "searches the superclass before a module included in the superclass" do
      ConstantSpecs::ParentB::CS_CONST203 = :const203_1
      ConstantSpecs::ModuleE::CS_CONST203 = :const203_2

      ConstantSpecs::ContainerB::ChildB.const203.should == :const203_1
      ConstantSpecs::ContainerB::ChildB.new.const203.should == :const203_1
    end

    it "searches a module included in the superclass" do
      ConstantSpecs::ModuleA::CS_CONST204 = :const204_2
      ConstantSpecs::ModuleE::CS_CONST204 = :const204_1

      ConstantSpecs::ContainerB::ChildB.const204.should == :const204_1
      ConstantSpecs::ContainerB::ChildB.new.const204.should == :const204_1
    end

    it "searches the superclass chain" do
      ConstantSpecs::ModuleA::CS_CONST205 = :const205

      ConstantSpecs::ContainerB::ChildB.const205.should == :const205
      ConstantSpecs::ContainerB::ChildB.new.const205.should == :const205
    end

    it "searches the lexical scope of the method not the receiver's immediate class" do
      ConstantSpecs::ContainerB::ChildB::CS_CONST206 = :const206_2
      class ConstantSpecs::ContainerB::ChildB
        class << self
          CS_CONST206 = :const206_1
        end
      end

      ConstantSpecs::ContainerB::ChildB.const206.should == :const206_1
    end

    it "searches the lexical scope of a singleton method" do
      ConstantSpecs::CS_CONST207 = :const207_1
      ConstantSpecs::ClassB::CS_CONST207 = :const207_2

      ConstantSpecs::CS_CONST208.const207.should == :const207_1
    end

    it "does not search the lexical scope of the caller" do
      ConstantSpecs::ClassB::CS_CONST209 = :const209

      -> { ConstantSpecs::ClassB.const209 }.should raise_error(NameError)
    end

    it "searches the lexical scope of a block" do
      ConstantSpecs::ClassB::CS_CONST210 = :const210_1
      ConstantSpecs::ParentB::CS_CONST210 = :const210_2

      ConstantSpecs::ClassB.const210.should == :const210_1
    end

    it "searches Object as a lexical scope only if Object is explicitly opened" do
      Object::CS_CONST211 = :const211_1
      ConstantSpecs::ParentB::CS_CONST211 = :const211_2
      ConstantSpecs::ContainerB::ChildB.const211.should == :const211_1

      Object::CS_CONST212 = :const212_2
      ConstantSpecs::ParentB::CS_CONST212 = :const212_1
      ConstantSpecs::ContainerB::ChildB.const212.should == :const212_1
    end

    it "returns the updated value when a constant is reassigned" do
      ConstantSpecs::ParentB::CS_CONST213 = :const213_1
      ConstantSpecs::ContainerB::ChildB.const213.should == :const213_1
      ConstantSpecs::ContainerB::ChildB.new.const213.should == :const213_1

      -> {
        ConstantSpecs::ParentB::CS_CONST213 = :const213_2
      }.should complain(/already initialized constant/)
      ConstantSpecs::ContainerB::ChildB.const213.should == :const213_2
      ConstantSpecs::ContainerB::ChildB.new.const213.should == :const213_2
    end

    it "does not search the lexical scope of qualifying modules" do
      ConstantSpecs::ContainerB::CS_CONST214 = :const214

      -> do
        ConstantSpecs::ContainerB::ChildB.const214
      end.should raise_error(NameError)
    end
  end

  it "raises a NameError if no constant is defined in the search path" do
    -> { ConstantSpecs::ParentA.constx }.should raise_error(NameError)
  end

  it "sends #const_missing to the original class or module scope" do
    ConstantSpecs::ClassA.constx.should == :CS_CONSTX
    ConstantSpecs::ClassA.new.constx.should == :CS_CONSTX
  end
end

describe "Constant resolution within a singleton class (class << obj)" do
  it "works like normal classes or modules" do
    ConstantSpecs::CS_SINGLETON1.foo.should == 1
  end

  it "uses its own namespace for each object" do
    a = ConstantSpecs::CS_SINGLETON2[0].foo
    b = ConstantSpecs::CS_SINGLETON2[1].foo
    [a, b].should == [1, 2]
  end

  it "uses its own namespace for nested modules" do
    a = ConstantSpecs::CS_SINGLETON3[0].x
    b = ConstantSpecs::CS_SINGLETON3[1].x
    a.should_not equal(b)
  end

  it "allows nested modules to have proper resolution" do
    a = ConstantSpecs::CS_SINGLETON4_CLASSES[0].new
    b = ConstantSpecs::CS_SINGLETON4_CLASSES[1].new
    [a.foo, b.foo].should == [1, 2]
  end
end

describe "top-level constant lookup" do
  context "on a class" do
    it "does not search Object after searching other scopes" do
      -> { String::Hash }.should raise_error(NameError)
    end
  end

  it "searches Object unsuccessfully when searches on a module" do
    -> { Enumerable::Hash }.should raise_error(NameError)
  end
end

describe "Module#private_constant marked constants" do

  it "remain private even when updated" do
    mod = Module.new
    mod.const_set :Foo, true
    mod.send :private_constant, :Foo
    -> {
      mod.const_set :Foo, false
    }.should complain(/already initialized constant/)

    -> {mod::Foo}.should raise_error(NameError)
  end

  it "sends #const_missing to the original class or module" do
    mod = Module.new
    mod.const_set :Foo, true
    mod.send :private_constant, :Foo
    def mod.const_missing(name)
      name == :Foo ? name : super
    end

    mod::Foo.should == :Foo
  end

  describe "in a module" do
    it "cannot be accessed from outside the module" do
      -> do
        ConstantVisibility::PrivConstModule::PRIVATE_CONSTANT_MODULE
      end.should raise_error(NameError)
    end

    it "cannot be reopened as a module from scope where constant would be private" do
      -> do
        module ConstantVisibility::ModuleContainer::PrivateModule; end
      end.should raise_error(NameError)
    end

    it "cannot be reopened as a class from scope where constant would be private" do
      -> do
        class ConstantVisibility::ModuleContainer::PrivateClass; end
      end.should raise_error(NameError)
    end

    it "can be reopened as a module where constant is not private" do
      module ::ConstantVisibility::ModuleContainer
        module PrivateModule
          X = 1
        end

        PrivateModule::X.should == 1
      end
    end

    it "can be reopened as a class where constant is not private" do
      module ::ConstantVisibility::ModuleContainer
        class PrivateClass
          X = 1
        end

        PrivateClass::X.should == 1
      end
    end

    it "is not defined? with A::B form" do
      defined?(ConstantVisibility::PrivConstModule::PRIVATE_CONSTANT_MODULE).should == nil
    end

    it "can be accessed from the module itself" do
      ConstantVisibility::PrivConstModule.private_constant_from_self.should be_true
    end

    it "is defined? from the module itself" do
      ConstantVisibility::PrivConstModule.defined_from_self.should == "constant"
    end

    it "can be accessed from lexical scope" do
      ConstantVisibility::PrivConstModule::Nested.private_constant_from_scope.should be_true
    end

    it "is defined? from lexical scope" do
      ConstantVisibility::PrivConstModule::Nested.defined_from_scope.should == "constant"
    end

    it "can be accessed from classes that include the module" do
      ConstantVisibility::ClassIncludingPrivConstModule.new.private_constant_from_include.should be_true
    end

    it "can be accessed from modules that include the module" do
      ConstantVisibility::ModuleIncludingPrivConstModule.private_constant_from_include.should be_true
    end

    it "raises a NameError when accessed directly from modules that include the module" do
      -> do
        ConstantVisibility::ModuleIncludingPrivConstModule.private_constant_self_from_include
      end.should raise_error(NameError)
      -> do
        ConstantVisibility::ModuleIncludingPrivConstModule.private_constant_named_from_include
      end.should raise_error(NameError)
    end

    it "is defined? from classes that include the module" do
      ConstantVisibility::ClassIncludingPrivConstModule.new.defined_from_include.should == "constant"
    end
  end

  describe "in a class" do
    it "cannot be accessed from outside the class" do
      -> do
        ConstantVisibility::PrivConstClass::PRIVATE_CONSTANT_CLASS
      end.should raise_error(NameError)
    end

    it "cannot be reopened as a module" do
      -> do
        module ConstantVisibility::ClassContainer::PrivateModule; end
      end.should raise_error(NameError)
    end

    it "cannot be reopened as a class" do
      -> do
        class ConstantVisibility::ClassContainer::PrivateClass; end
      end.should raise_error(NameError)
    end

    it "can be reopened as a module where constant is not private" do
      class ::ConstantVisibility::ClassContainer
        module PrivateModule
          X = 1
        end

        PrivateModule::X.should == 1
      end
    end

    it "can be reopened as a class where constant is not private" do
      class ::ConstantVisibility::ClassContainer
        class PrivateClass
          X = 1
        end

        PrivateClass::X.should == 1
      end
    end

    it "is not defined? with A::B form" do
      defined?(ConstantVisibility::PrivConstClass::PRIVATE_CONSTANT_CLASS).should == nil
    end

    it "can be accessed from the class itself" do
      ConstantVisibility::PrivConstClass.private_constant_from_self.should be_true
    end

    it "is defined? from the class itself" do
      ConstantVisibility::PrivConstClass.defined_from_self.should == "constant"
    end

    it "can be accessed from lexical scope" do
      ConstantVisibility::PrivConstClass::Nested.private_constant_from_scope.should be_true
    end

    it "is defined? from lexical scope" do
      ConstantVisibility::PrivConstClass::Nested.defined_from_scope.should == "constant"
    end

    it "can be accessed from subclasses" do
      ConstantVisibility::PrivConstClassChild.new.private_constant_from_subclass.should be_true
    end

    it "is defined? from subclasses" do
      ConstantVisibility::PrivConstClassChild.new.defined_from_subclass.should == "constant"
    end
  end

  describe "in Object" do
    it "cannot be accessed using ::Const form" do
      -> do
        ::PRIVATE_CONSTANT_IN_OBJECT
      end.should raise_error(NameError)
    end

    it "is not defined? using ::Const form" do
      defined?(::PRIVATE_CONSTANT_IN_OBJECT).should == nil
    end

    it "can be accessed through the normal search" do
      PRIVATE_CONSTANT_IN_OBJECT.should == true
    end

    it "is defined? through the normal search" do
      defined?(PRIVATE_CONSTANT_IN_OBJECT).should == "constant"
    end
  end

  describe "NameError by #private_constant" do
    it "has :receiver and :name attributes" do
      -> do
        ConstantVisibility::PrivConstClass::PRIVATE_CONSTANT_CLASS
      end.should raise_error(NameError) {|e|
        e.receiver.should == ConstantVisibility::PrivConstClass
        e.name.should == :PRIVATE_CONSTANT_CLASS
      }

      -> do
        ConstantVisibility::PrivConstModule::PRIVATE_CONSTANT_MODULE
      end.should raise_error(NameError) {|e|
        e.receiver.should == ConstantVisibility::PrivConstModule
        e.name.should == :PRIVATE_CONSTANT_MODULE
      }
    end

    it "has the defined class as the :name attribute" do
      -> do
        ConstantVisibility::PrivConstClassChild::PRIVATE_CONSTANT_CLASS
      end.should raise_error(NameError) {|e|
        e.receiver.should == ConstantVisibility::PrivConstClass
        e.name.should == :PRIVATE_CONSTANT_CLASS
      }

      -> do
        ConstantVisibility::ClassIncludingPrivConstModule::PRIVATE_CONSTANT_MODULE
      end.should raise_error(NameError) {|e|
        e.receiver.should == ConstantVisibility::PrivConstModule
        e.name.should == :PRIVATE_CONSTANT_MODULE
      }
    end
  end
end

describe "Module#public_constant marked constants" do
  before :each do
    @module = ConstantVisibility::PrivConstModule.dup
  end

  describe "in a module" do
    it "can be accessed from outside the module" do
      @module.send :public_constant, :PRIVATE_CONSTANT_MODULE
      @module::PRIVATE_CONSTANT_MODULE.should == true
    end

    it "is defined? with A::B form" do
      @module.send :public_constant, :PRIVATE_CONSTANT_MODULE
      defined?(@module::PRIVATE_CONSTANT_MODULE).should == "constant"
    end
  end

  describe "in a class" do
    before :each do
      @class = ConstantVisibility::PrivConstClass.dup
    end

    it "can be accessed from outside the class" do
      @class.send :public_constant, :PRIVATE_CONSTANT_CLASS
      @class::PRIVATE_CONSTANT_CLASS.should == true
    end

    it "is defined? with A::B form" do
      @class.send :public_constant, :PRIVATE_CONSTANT_CLASS
      defined?(@class::PRIVATE_CONSTANT_CLASS).should == "constant"
    end
  end

  describe "in Object" do
    after :each do
      ConstantVisibility.reset_private_constants
    end

    it "can be accessed using ::Const form" do
      Object.send :public_constant, :PRIVATE_CONSTANT_IN_OBJECT
      ::PRIVATE_CONSTANT_IN_OBJECT.should == true
    end

    it "is defined? using ::Const form" do
      Object.send :public_constant, :PRIVATE_CONSTANT_IN_OBJECT
      defined?(::PRIVATE_CONSTANT_IN_OBJECT).should == "constant"
    end
  end
end

describe 'Allowed characters' do
  it 'allows not ASCII characters in the middle of a name' do
    mod = Module.new
    mod.const_set("BBἍBB", 1)

    eval("mod::BBἍBB").should == 1
  end

  it 'does not allow not ASCII characters that cannot be upcased or lowercased at the beginning' do
    -> do
      Module.new.const_set("થBB", 1)
    end.should raise_error(NameError, /wrong constant name/)
  end

  it 'allows not ASCII upcased characters at the beginning' do
    mod = Module.new
    mod.const_set("ἍBB", 1)

    eval("mod::ἍBB").should == 1
  end
end

describe 'Assignment' do
  context 'dynamic assignment' do
    it 'raises SyntaxError' do
      -> do
        eval <<-CODE
          def test
            B = 1
          end
        CODE
      end.should raise_error(SyntaxError, /dynamic constant assignment/)
    end
  end
end
