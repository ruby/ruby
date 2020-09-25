require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#descendants" do
  describe "when called on a class" do
    it "returns a list of classes descended from self (including self)" do
      assert_descendants(ModuleSpecs::Parent, [ModuleSpecs::Parent, ModuleSpecs::Child, ModuleSpecs::Child2, ModuleSpecs::Grandchild])
    end

    it "does not return included modules" do
      parent = Class.new
      child = Class.new(parent)
      mod = Module.new
      parent.include(mod)

      parent.descendants.should_not include(mod)
    end

    it "does not return singleton classes" do
      a = Class.new

      a_obj = a.new
      def a_obj.force_singleton_class
        42
      end

      a.descendants.should_not include(a_obj.singleton_class)
    end
  end

  describe "when called on a module" do
    it "returns a list of modules and classes including self (including module itself)" do
      a = Module.new
      b = Module.new { include a }
      c = Module.new { include b }
      klass1 = Class.new
      klass1.include(a)
      klass2 = Class.new
      klass2.include(b)

      assert_descendants(a, [a, b, c, klass1, klass2])
    end
  end

  it "has 1 entry per module or class" do
    ModuleSpecs::Parent.descendants.should == ModuleSpecs::Parent.descendants.uniq
  end

  def assert_descendants(mod, descendants)
    mod.descendants.map(&:inspect).sort.should == descendants.map(&:inspect).sort
  end
end
