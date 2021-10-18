require_relative '../../spec_helper'
require_relative '../module/fixtures/classes'

ruby_version_is '3.1' do
  describe "Class#descendants" do
    it "returns a list of classes descended from self (excluding self)" do
      assert_descendants(ModuleSpecs::Parent, [ModuleSpecs::Child, ModuleSpecs::Child2, ModuleSpecs::Grandchild])
    end

    it "does not return included modules" do
      parent = Class.new
      child = Class.new(parent)
      mod = Module.new
      parent.include(mod)

      assert_descendants(parent, [child])
    end

    it "does not return singleton classes" do
      a = Class.new

      a_obj = a.new
      def a_obj.force_singleton_class
        42
      end

      a.descendants.should_not include(a_obj.singleton_class)
    end

    it "has 1 entry per module or class" do
      ModuleSpecs::Parent.descendants.should == ModuleSpecs::Parent.descendants.uniq
    end

    def assert_descendants(mod, descendants)
      mod.descendants.sort_by(&:inspect).should == descendants.sort_by(&:inspect)
    end
  end
end
