require_relative '../../spec_helper'
require_relative '../module/fixtures/classes'

ruby_version_is '3.1' do
  describe "Class#subclasses" do
    it "returns a list of classes directly inheriting from self" do
      assert_subclasses(ModuleSpecs::Parent, [ModuleSpecs::Child, ModuleSpecs::Child2])
    end

    it "does not return included modules" do
      parent = Class.new
      child = Class.new(parent)
      mod = Module.new
      parent.include(mod)

      assert_subclasses(parent, [child])
    end

    it "does not return singleton classes" do
      a = Class.new

      a_obj = a.new
      def a_obj.force_singleton_class
        42
      end

      a.subclasses.should_not include(a_obj.singleton_class)
    end

    it "has 1 entry per module or class" do
      ModuleSpecs::Parent.subclasses.should == ModuleSpecs::Parent.subclasses.uniq
    end

    def assert_subclasses(mod,subclasses)
      mod.subclasses.sort_by(&:inspect).should == subclasses.sort_by(&:inspect)
    end
  end
end
