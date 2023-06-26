require_relative 'spec_helper'
require_relative 'fixtures/class'
require_relative '../../core/module/fixtures/classes'

load_extension("class")
compile_extension("class_under_autoload")
compile_extension("class_id_under_autoload")

autoload :ClassUnderAutoload, "#{object_path}/class_under_autoload_spec"
autoload :ClassIdUnderAutoload, "#{object_path}/class_id_under_autoload_spec"

describe :rb_path_to_class, shared: true do
  it "returns a class or module from a scoped String" do
    @s.send(@method, "CApiClassSpecs::A::B").should equal(CApiClassSpecs::A::B)
    @s.send(@method, "CApiClassSpecs::A::M").should equal(CApiClassSpecs::A::M)
  end

  it "resolves autoload constants" do
    @s.send(@method, "CApiClassSpecs::A::D").name.should == "CApiClassSpecs::A::D"
  end

  it "raises an ArgumentError if a constant in the path does not exist" do
    -> { @s.send(@method, "CApiClassSpecs::NotDefined::B") }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if the final constant does not exist" do
    -> { @s.send(@method, "CApiClassSpecs::NotDefined") }.should raise_error(ArgumentError)
  end

  it "raises a TypeError if the constant is not a class or module" do
    -> {
      @s.send(@method, "CApiClassSpecs::A::C")
    }.should raise_error(TypeError, 'CApiClassSpecs::A::C does not refer to class/module')
  end

  it "raises an ArgumentError even if a constant in the path exists on toplevel" do
    -> { @s.send(@method, "CApiClassSpecs::Object") }.should raise_error(ArgumentError)
  end
end

describe "C-API Class function" do
  before :each do
    @s = CApiClassSpecs.new
  end

  describe "rb_class_instance_methods" do
    it "returns the public and protected methods of self and its ancestors" do
      methods = @s.rb_class_instance_methods(ModuleSpecs::Basic)
      methods.should include(:protected_module, :public_module)

      methods = @s.rb_class_instance_methods(ModuleSpecs::Basic, true)
      methods.should include(:protected_module, :public_module)
    end

    it "when passed false as a parameter, returns the instance methods of the class" do
      methods = @s.rb_class_instance_methods(ModuleSpecs::Child, false)
      methods.should include(:protected_child, :public_child)
    end
  end

  describe "rb_class_public_instance_methods" do
    it "returns a list of public methods in module and its ancestors" do
      methods = @s.rb_class_public_instance_methods(ModuleSpecs::CountsChild)
      methods.should include(:public_3)
      methods.should include(:public_2)
      methods.should include(:public_1)

      methods = @s.rb_class_public_instance_methods(ModuleSpecs::CountsChild, true)
      methods.should include(:public_3)
      methods.should include(:public_2)
      methods.should include(:public_1)
    end

    it "when passed false as a parameter, should return only methods defined in that module" do
      @s.rb_class_public_instance_methods(ModuleSpecs::CountsChild, false).should == [:public_1]
    end
  end

  describe "rb_class_protected_instance_methods" do
    it "returns a list of protected methods in module and its ancestors" do
      methods = @s.rb_class_protected_instance_methods(ModuleSpecs::CountsChild)
      methods.should include(:protected_3)
      methods.should include(:protected_2)
      methods.should include(:protected_1)

      methods = @s.rb_class_protected_instance_methods(ModuleSpecs::CountsChild, true)
      methods.should include(:protected_3)
      methods.should include(:protected_2)
      methods.should include(:protected_1)
    end

    it "when passed false as a parameter, should return only methods defined in that module" do
      @s.rb_class_public_instance_methods(ModuleSpecs::CountsChild, false).should == [:public_1]
    end
  end

  describe "rb_class_private_instance_methods" do
    it "returns a list of private methods in module and its ancestors" do
      @s.rb_class_private_instance_methods(ModuleSpecs::CountsChild).should == ModuleSpecs::CountsChild.private_instance_methods
      @s.rb_class_private_instance_methods(ModuleSpecs::CountsChild, true).should == ModuleSpecs::CountsChild.private_instance_methods
    end

    it "when passed false as a parameter, should return only methods defined in that module" do
      methods = @s.rb_class_private_instance_methods(ModuleSpecs::CountsChild, false)
      methods.should == [:private_1]
    end
  end

  describe "rb_class_new_instance" do
    it "allocates and initializes a new object" do
      o = @s.rb_class_new_instance([], CApiClassSpecs::Alloc)
      o.class.should == CApiClassSpecs::Alloc
      o.initialized.should be_true
    end

    it "passes arguments to the #initialize method" do
      o = @s.rb_class_new_instance([:one, :two], CApiClassSpecs::Alloc)
      o.arguments.should == [:one, :two]
    end
  end

  describe "rb_class_new_instance_kw" do
    it "passes arguments and keywords to the #initialize method" do
      obj = @s.rb_class_new_instance_kw([{pos: 1}, {kw: 2}], CApiClassSpecs::KeywordAlloc)
      obj.args.should == [{pos: 1}]
      obj.kwargs.should == {kw: 2}

      obj = @s.rb_class_new_instance_kw([{}], CApiClassSpecs::KeywordAlloc)
      obj.args.should == []
      obj.kwargs.should == {}
    end

    it "raises TypeError if the last argument is not a Hash" do
      -> {
        @s.rb_class_new_instance_kw([42], CApiClassSpecs::KeywordAlloc)
      }.should raise_error(TypeError, 'no implicit conversion of Integer into Hash')
    end
  end

  describe "rb_include_module" do
    it "includes a module into a class" do
      c = Class.new
      o = c.new
      -> { o.included? }.should raise_error(NameError)
      @s.rb_include_module(c, CApiClassSpecs::M)
      o.included?.should be_true
    end
  end

  describe "rb_define_attr" do
    before :each do
      @a = CApiClassSpecs::Attr.new
    end

    it "defines an attr_reader when passed true, false" do
      @s.rb_define_attr(CApiClassSpecs::Attr, :foo, true, false)
      @a.foo.should == 1
      -> { @a.foo = 5 }.should raise_error(NameError)
    end

    it "defines an attr_writer when passed false, true" do
      @s.rb_define_attr(CApiClassSpecs::Attr, :bar, false, true)
      -> { @a.bar }.should raise_error(NameError)
      @a.bar = 5
      @a.instance_variable_get(:@bar).should == 5
    end

    it "defines an attr_accessor when passed true, true" do
      @s.rb_define_attr(CApiClassSpecs::Attr, :baz, true, true)
      @a.baz.should == 3
      @a.baz = 6
      @a.baz.should == 6
    end
  end

  describe "rb_call_super" do
    it "calls the method in the superclass" do
      @s.define_call_super_method CApiClassSpecs::Sub, "call_super_method"
      obj = CApiClassSpecs::Sub.new
      obj.call_super_method.should == :super_method
    end

    it "calls the method in the superclass with the correct self" do
      @s.define_call_super_method CApiClassSpecs::SubSelf, "call_super_method"
      obj = CApiClassSpecs::SubSelf.new
      obj.call_super_method.should equal obj
    end

    it "calls the method in the superclass through two native levels" do
      @s.define_call_super_method CApiClassSpecs::Sub, "call_super_method"
      @s.define_call_super_method CApiClassSpecs::SubSub, "call_super_method"
      obj = CApiClassSpecs::SubSub.new
      obj.call_super_method.should == :super_method
    end
  end

  describe "rb_class2name" do
    it "returns the class name" do
      @s.rb_class2name(CApiClassSpecs).should == "CApiClassSpecs"
    end

    it "returns a string for an anonymous class" do
      @s.rb_class2name(Class.new).should be_kind_of(String)
    end

    it "returns a string beginning with # for an anonymous class" do
      @s.rb_class2name(Struct.new(:x, :y).new(1, 2).class).should.start_with?('#')
    end
  end

  describe "rb_class_path" do
    it "returns a String of a class path with no scope modifiers" do
      @s.rb_class_path(Array).should == "Array"
    end

    it "returns a String of a class path with scope modifiers" do
      @s.rb_class_path(File::Stat).should == "File::Stat"
    end
  end

  describe "rb_class_name" do
    it "returns the class name" do
      @s.rb_class_name(CApiClassSpecs).should == "CApiClassSpecs"
    end

    it "returns a string for an anonymous class" do
      @s.rb_class_name(Class.new).should be_kind_of(String)
    end
  end

  describe "rb_path2class" do
    it_behaves_like :rb_path_to_class, :rb_path2class
  end

  describe "rb_path_to_class" do
    it_behaves_like :rb_path_to_class, :rb_path_to_class
  end

  describe "rb_cvar_defined" do
    it "returns false when the class variable is not defined" do
      @s.rb_cvar_defined(CApiClassSpecs::CVars, "@@nocvar").should be_false
    end

    it "returns true when the class variable is defined" do
      @s.rb_cvar_defined(CApiClassSpecs::CVars, "@@cvar").should be_true
    end

    it "returns true if the class instance variable is defined" do
      @s.rb_cvar_defined(CApiClassSpecs::CVars, "@c_ivar").should be_true
    end
  end

  describe "rb_cv_set" do
    it "sets a class variable" do
      o = CApiClassSpecs::CVars.new
      o.new_cv.should be_nil
      @s.rb_cv_set(CApiClassSpecs::CVars, "@@new_cv", 1)
      o.new_cv.should == 1
      CApiClassSpecs::CVars.remove_class_variable :@@new_cv
    end
  end

  describe "rb_cv_get" do
    it "returns the value of the class variable" do
      @s.rb_cvar_get(CApiClassSpecs::CVars, "@@cvar").should == :cvar
    end

    it "raises a NameError if the class variable is not defined" do
      -> {
        @s.rb_cv_get(CApiClassSpecs::CVars, "@@no_cvar")
      }.should raise_error(NameError, /class variable @@no_cvar/)
    end
  end

  describe "rb_cvar_set" do
    it "sets a class variable" do
      o = CApiClassSpecs::CVars.new
      o.new_cvar.should be_nil
      @s.rb_cvar_set(CApiClassSpecs::CVars, "@@new_cvar", 1)
      o.new_cvar.should == 1
      CApiClassSpecs::CVars.remove_class_variable :@@new_cvar
    end

  end

  describe "rb_define_class" do
    before :each do
      @cls = @s.rb_define_class("ClassSpecDefineClass", CApiClassSpecs::Super)
    end

    it "creates a subclass of the superclass" do
      @cls.should be_kind_of(Class)
      ClassSpecDefineClass.should equal(@cls)
      @cls.superclass.should == CApiClassSpecs::Super
    end

    it "sets the class name" do
      @cls.name.should == "ClassSpecDefineClass"
    end

    it "calls #inherited on the superclass" do
      CApiClassSpecs::Super.should_receive(:inherited)
      @s.rb_define_class("ClassSpecDefineClass2", CApiClassSpecs::Super)
      Object.send(:remove_const, :ClassSpecDefineClass2)
    end

    it "raises a TypeError when given a non class object to superclass" do
      -> {
        @s.rb_define_class("ClassSpecDefineClass3", Module.new)
      }.should raise_error(TypeError)
    end

    it "raises a TypeError when given a mismatched class to superclass" do
      -> {
        @s.rb_define_class("ClassSpecDefineClass", Object)
      }.should raise_error(TypeError)
    end

    it "raises a ArgumentError when given NULL as superclass" do
      -> {
        @s.rb_define_class("ClassSpecDefineClass4", nil)
      }.should raise_error(ArgumentError)
    end

    it "allows arbitrary names, including constant names not valid in Ruby" do
      cls = @s.rb_define_class("_INVALID_CLASS", CApiClassSpecs::Super)
      cls.name.should == "_INVALID_CLASS"

      -> {
        Object.const_get(cls.name)
      }.should raise_error(NameError, /wrong constant name/)
    end
  end

  describe "rb_define_class_under" do
    it "creates a subclass of the superclass contained in a module" do
      cls = @s.rb_define_class_under(CApiClassSpecs,
                                     "ClassUnder1",
                                     CApiClassSpecs::Super)
      cls.should be_kind_of(Class)
      CApiClassSpecs::Super.should be_ancestor_of(CApiClassSpecs::ClassUnder1)
    end

    it "sets the class name" do
      cls = @s.rb_define_class_under(CApiClassSpecs, "ClassUnder3", Object)
      cls.name.should == "CApiClassSpecs::ClassUnder3"
    end

    it "calls #inherited on the superclass" do
      CApiClassSpecs::Super.should_receive(:inherited)
      @s.rb_define_class_under(CApiClassSpecs, "ClassUnder4", CApiClassSpecs::Super)
      CApiClassSpecs.send(:remove_const, :ClassUnder4)
    end

    it "raises a TypeError when given a non class object to superclass" do
      -> { @s.rb_define_class_under(CApiClassSpecs,
                                        "ClassUnder5",
                                        Module.new)
      }.should raise_error(TypeError)
    end

    it "raises a TypeError when given a mismatched class to superclass" do
      CApiClassSpecs::ClassUnder6 = Class.new(CApiClassSpecs::Super)
      -> { @s.rb_define_class_under(CApiClassSpecs,
                                        "ClassUnder6",
                                        Class.new)
      }.should raise_error(TypeError)
    end

    it "defines a class for an existing Autoload" do
      ClassUnderAutoload.name.should == "ClassUnderAutoload"
    end

    it "raises a TypeError if class is defined and its superclass mismatches the given one" do
      -> { @s.rb_define_class_under(CApiClassSpecs, "Sub", Object) }.should raise_error(TypeError)
    end

    it "allows arbitrary names, including constant names not valid in Ruby" do
      cls = @s.rb_define_class_under(CApiClassSpecs, "_INVALID_CLASS", CApiClassSpecs::Super)
      cls.name.should == "CApiClassSpecs::_INVALID_CLASS"

      -> {
        CApiClassSpecs.const_get(cls.name)
      }.should raise_error(NameError, /wrong constant name/)
    end
  end

  describe "rb_define_class_id_under" do
    it "creates a subclass of the superclass contained in a module" do
      cls = @s.rb_define_class_id_under(CApiClassSpecs, :ClassIdUnder1, CApiClassSpecs::Super)
      cls.should be_kind_of(Class)
      CApiClassSpecs::Super.should be_ancestor_of(CApiClassSpecs::ClassIdUnder1)
    end

    it "sets the class name" do
      cls = @s.rb_define_class_id_under(CApiClassSpecs, :ClassIdUnder3, Object)
      cls.name.should == "CApiClassSpecs::ClassIdUnder3"
    end

    it "calls #inherited on the superclass" do
      CApiClassSpecs::Super.should_receive(:inherited)
      @s.rb_define_class_id_under(CApiClassSpecs, :ClassIdUnder4, CApiClassSpecs::Super)
      CApiClassSpecs.send(:remove_const, :ClassIdUnder4)
    end

    it "defines a class for an existing Autoload" do
      ClassIdUnderAutoload.name.should == "ClassIdUnderAutoload"
    end

    it "raises a TypeError if class is defined and its superclass mismatches the given one" do
      -> { @s.rb_define_class_id_under(CApiClassSpecs, :Sub, Object) }.should raise_error(TypeError)
    end

    it "allows arbitrary names, including constant names not valid in Ruby" do
      cls = @s.rb_define_class_id_under(CApiClassSpecs, :_INVALID_CLASS2, CApiClassSpecs::Super)
      cls.name.should == "CApiClassSpecs::_INVALID_CLASS2"

      -> {
        CApiClassSpecs.const_get(cls.name)
      }.should raise_error(NameError, /wrong constant name/)
    end
  end

  describe "rb_define_class_variable" do
    it "sets a class variable" do
      o = CApiClassSpecs::CVars.new
      o.rbdcv_cvar.should be_nil
      @s.rb_define_class_variable(CApiClassSpecs::CVars, "@@rbdcv_cvar", 1)
      o.rbdcv_cvar.should == 1
      CApiClassSpecs::CVars.remove_class_variable :@@rbdcv_cvar
    end
  end

  describe "rb_cvar_get" do
    it "returns the value of the class variable" do
      @s.rb_cvar_get(CApiClassSpecs::CVars, "@@cvar").should == :cvar
    end

    it "raises a NameError if the class variable is not defined" do
      -> {
        @s.rb_cvar_get(CApiClassSpecs::CVars, "@@no_cvar")
      }.should raise_error(NameError, /class variable @@no_cvar/)
    end
  end

  describe "rb_class_new" do
    it "returns a new subclass of the superclass" do
      subclass = @s.rb_class_new(CApiClassSpecs::NewClass)
      CApiClassSpecs::NewClass.should be_ancestor_of(subclass)
    end

    it "raises a TypeError if passed Class as the superclass" do
      -> { @s.rb_class_new(Class) }.should raise_error(TypeError)
    end

    it "raises a TypeError if passed a singleton class as the superclass" do
      metaclass = Object.new.singleton_class
      -> { @s.rb_class_new(metaclass) }.should raise_error(TypeError)
    end
  end

  describe "rb_class_superclass" do
    it "returns the superclass of a class" do
      cls = @s.rb_class_superclass(CApiClassSpecs::Sub)
      cls.should == CApiClassSpecs::Super
    end

    it "returns nil if the class has no superclass" do
      @s.rb_class_superclass(BasicObject).should be_nil
    end
  end

  describe "rb_class_real" do
    it "returns the class of an object ignoring the singleton class" do
      obj = CApiClassSpecs::Sub.new
      def obj.some_method() end

      @s.rb_class_real(obj).should == CApiClassSpecs::Sub
    end

    it "returns the class of an object ignoring included modules" do
      obj = CApiClassSpecs::SubM.new
      @s.rb_class_real(obj).should == CApiClassSpecs::SubM
    end

    it "returns 0 if passed 0" do
      @s.rb_class_real(0).should == 0
    end
  end
end
