require_relative '../../spec_helper'

describe "Kernel#initialize_dup" do
  it "is a private instance method" do
    Kernel.should have_private_instance_method(:initialize_dup)
  end

  it "returns the receiver" do
    a = Object.new
    b = Object.new
    a.send(:initialize_dup, b).should == a
  end

  it "calls #initialize_copy" do
    a = Object.new
    b = Object.new
    a.should_receive(:initialize_copy).with(b)
    a.send(:initialize_dup, b)
  end
end
