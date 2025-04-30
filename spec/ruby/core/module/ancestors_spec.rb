require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#ancestors" do
  it "returns a list of modules included in self (including self)" do
    BasicObject.ancestors.should == [BasicObject]
    ModuleSpecs.ancestors.should == [ModuleSpecs]
    ModuleSpecs::Basic.ancestors.should == [ModuleSpecs::Basic]
    ModuleSpecs::Super.ancestors.should == [ModuleSpecs::Super, ModuleSpecs::Basic]
    if Namespace.enabled?
      ModuleSpecs.without_test_modules(ModuleSpecs::Parent.ancestors).should ==
        [ModuleSpecs::Parent, Object, Namespace::Loader, Kernel, BasicObject]
      ModuleSpecs.without_test_modules(ModuleSpecs::Child.ancestors).should ==
        [ModuleSpecs::Child, ModuleSpecs::Super, ModuleSpecs::Basic, ModuleSpecs::Parent, Object, Namespace::Loader, Kernel, BasicObject]
    else
      ModuleSpecs.without_test_modules(ModuleSpecs::Parent.ancestors).should ==
        [ModuleSpecs::Parent, Object, Kernel, BasicObject]
      ModuleSpecs.without_test_modules(ModuleSpecs::Child.ancestors).should ==
        [ModuleSpecs::Child, ModuleSpecs::Super, ModuleSpecs::Basic, ModuleSpecs::Parent, Object, Kernel, BasicObject]
    end
  end

  it "returns only modules and classes" do
    class << ModuleSpecs::Child; self; end.ancestors.should include(ModuleSpecs::Internal, Class, Module, Object, Kernel)
  end

  it "has 1 entry per module or class" do
    ModuleSpecs::Parent.ancestors.should == ModuleSpecs::Parent.ancestors.uniq
  end

  it "returns a module that is included later into a nested module as well" do
    m1 = Module.new
    m2 = Module.new
    m3 = Module.new do
      include m2
    end
    m2.include m1 # should be after m3 includes m2

    m3.ancestors.should == [m3, m2, m1]
  end

  describe "when called on a singleton class" do
    it "includes the singleton classes of ancestors" do
      parent  = Class.new
      child   = Class.new(parent)
      schild  = child.singleton_class

      schild.ancestors.should include(schild,
                                      parent.singleton_class,
                                      Object.singleton_class,
                                      BasicObject.singleton_class,
                                      Class,
                                      Module,
                                      Object,
                                      Kernel,
                                      BasicObject)

    end

    describe 'for a standalone module' do
      it 'does not include Class' do
        s_mod = ModuleSpecs.singleton_class
        s_mod.ancestors.should_not include(Class)
      end

      it 'does not include other singleton classes' do
        s_standalone_mod = ModuleSpecs.singleton_class
        s_module = Module.singleton_class
        s_object = Object.singleton_class
        s_basic_object = BasicObject.singleton_class

        s_standalone_mod.ancestors.should_not include(s_module, s_object, s_basic_object)
      end

      it 'includes its own singleton class' do
        s_mod = ModuleSpecs.singleton_class

        s_mod.ancestors.should include(s_mod)
      end

      it 'includes standard chain' do
        s_mod = ModuleSpecs.singleton_class

        s_mod.ancestors.should include(Module, Object, Kernel, BasicObject)
      end
    end
  end
end
