require_relative '../../spec_helper'
require_relative 'fixtures/__owner__'

describe "Kernel.__owner__" do
  it "returns correct owner when called from a supermethod" do
    KernelSpecs::OwnerTest.new.m0.should == KernelSpecs::OwnerTestModule
  end

  it "returns correct owner when called from a supermethod that's accessed by super_method" do
    KernelSpecs::OwnerTest.new.method(:m0).super_method.call.should == KernelSpecs::OwnerTestModule
  end

  it "returns correct owner when called from an alias" do
    KernelSpecs::OwnerTest.new.m0_alias.should == KernelSpecs::OwnerTestModule
  end

  it "returns correct owner when called from an alias method" do
    KernelSpecs::OwnerTest.new.m0_alias_method.should == KernelSpecs::OwnerTestModule
  end

  it "returns correct owner when called from an alias in a subclass" do
    KernelSpecs::OwnerTest.new.m1_alias.should == KernelSpecs::OwnerTestModule
  end

  it "returns correct owner when called from an alias method in a subclass" do
    KernelSpecs::OwnerTest.new.m1_alias_method.should == KernelSpecs::OwnerTestModule
  end

  it "returns correct owner even the called from a block" do
    KernelSpecs::OwnerTest.new.in_block.should == [KernelSpecs::OwnerTestModule]
  end

  it "returns correct owner when called from a method defined using define_method" do
    KernelSpecs::OwnerTest.new.dm.should == KernelSpecs::OwnerTestModule
  end

  it "returns correct owner when called from a block inside a method defined using define_method" do
    KernelSpecs::OwnerTest.new.dm_block.should == [KernelSpecs::OwnerTestModule]
  end

  it "returns correct owner when called using send" do
    KernelSpecs::OwnerTest.new.from_send.should == KernelSpecs::OwnerTestModule
  end

  it "returns correct owner when called using eval" do
    KernelSpecs::OwnerTest.new.from_eval.should == KernelSpecs::OwnerTestModule
  end

  it "returns nil when called inside a class body" do
    KernelSpecs::OwnerTest.new.from_class_body.should == nil
  end

  it "returns nil when not called from a method" do
    __owner__.should == nil
  end
end
