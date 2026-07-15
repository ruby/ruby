require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#Array" do
  before :each do
    @array = [1, 2, 3]
  end

  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:Array)
  end

  it "does not call #to_ary on an Array" do
    @array.should_not_receive(:to_ary)
    Array(@array).should == @array
  end

  it "calls #to_ary to convert the argument to an Array" do
    obj = mock("Array([1,2,3])")
    obj.should_receive(:to_ary).and_return(@array)
    obj.should_not_receive(:to_a)

    Array(obj).should == @array
  end

  it "does not call #to_a on an Array" do
    @array.should_not_receive(:to_a)
    Array(@array).should == @array
  end

  it "calls #to_a if the argument does not respond to #to_ary" do
    obj = mock("Array([1,2,3])")
    obj.should_receive(:to_a).and_return(@array)

    Array(obj).should == @array
  end

  it "calls #to_a if #to_ary returns nil" do
    obj = mock("Array([1,2,3])")
    obj.should_receive(:to_ary).and_return(nil)
    obj.should_receive(:to_a).and_return(@array)

    Array(obj).should == @array
  end

  it "returns an Array containing the argument if #to_a returns nil" do
    obj = mock("Array([1,2,3])")
    obj.should_receive(:to_a).and_return(nil)

    Array(obj).should == [obj]
  end

  it "calls #to_ary first, even if it's private" do
    obj = KernelSpecs::PrivateToAry.new

    Array(obj).should == [1, 2]
  end

  it "calls #to_a if #to_ary is not defined, even if it's private" do
    obj = KernelSpecs::PrivateToA.new

    Array(obj).should == [3, 4]
  end

  it "returns an Array containing the argument if it responds to neither #to_ary nor #to_a" do
    obj = mock("Array(x)")
    Array(obj).should == [obj]
  end

  it "returns an empty Array when passed nil" do
    Array(nil).should == []
  end

  it "raises a TypeError if #to_ary does not return an Array" do
    obj = mock("Array() string")
    obj.should_receive(:to_ary).and_return("string")

    -> { Array(obj) }.should.raise(TypeError)
  end

  it "raises a TypeError if #to_a does not return an Array" do
    obj = mock("Array() string")
    obj.should_receive(:to_a).and_return("string")

    -> { Array(obj) }.should.raise(TypeError)
  end
end

describe "Kernel.Array" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:Array)
  end
end
