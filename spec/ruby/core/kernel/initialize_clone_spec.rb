require_relative '../../spec_helper'

describe "Kernel#initialize_clone" do
  it "is a private instance method" do
    Kernel.should have_private_instance_method(:initialize_clone)
  end

  it "returns the receiver" do
    a = Object.new
    b = Object.new
    a.send(:initialize_clone, b).should == a
  end

  it "calls #initialize_copy" do
    a = Object.new
    b = Object.new
    a.should_receive(:initialize_copy).with(b)
    a.send(:initialize_clone, b)
  end

  it "accepts a :freeze keyword argument for obj.clone(freeze: value)" do
    a = Object.new
    b = Object.new
    a.send(:initialize_clone, b, freeze: true).should == a
  end
end
