require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#module_exec" do
  it "does not add defined methods to other classes" do
    FalseClass.module_exec do
      def foo
        'foo'
      end
    end
    -> {42.foo}.should.raise(NoMethodError)
  end

  it "defines method in the receiver's scope" do
    ModuleSpecs::Subclass.module_exec { def foo; end }
    ModuleSpecs::Subclass.new.respond_to?(:foo).should == true
  end

  it "evaluates a given block in the context of self" do
    ModuleSpecs::Subclass.module_exec { self }.should == ModuleSpecs::Subclass
    ModuleSpecs::Subclass.new.module_exec { 1 + 1 }.should == 2
  end

  it "raises a LocalJumpError when no block is given" do
    -> { ModuleSpecs::Subclass.module_exec }.should.raise(LocalJumpError)
  end

  it "passes arguments to the block" do
    a = ModuleSpecs::Subclass
    a.module_exec(1) { |b| b }.should.equal?(1)
  end

  describe "with optional argument" do
    it "does not destructure a single array argument" do
      ModuleSpecs::Subclass.module_exec([1, 2, 3]) { |a = 99| a }.should == [1, 2, 3]
    end
  end
end
