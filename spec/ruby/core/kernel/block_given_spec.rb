require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#block_given?" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:block_given?)
  end

  it "returns true if and only if a block is supplied" do
    KernelSpecs::BlockGiven.accept_block {}.should == true
    KernelSpecs::BlockGiven.accept_block_as_argument {}.should == true
    KernelSpecs::BlockGiven.accept_block_inside_block {}.should == true
    KernelSpecs::BlockGiven.accept_block_as_argument_inside_block {}.should == true

    KernelSpecs::BlockGiven.accept_block.should == false
    KernelSpecs::BlockGiven.accept_block_as_argument.should == false
    KernelSpecs::BlockGiven.accept_block_inside_block.should == false
    KernelSpecs::BlockGiven.accept_block_as_argument_inside_block.should == false
  end

  # Clarify: Based on http://www.ruby-forum.com/topic/137822 it appears
  # that Matz wanted this to be true in 1.9.
  it "returns false when a method defined by define_method is called with a block" do
    KernelSpecs::BlockGiven.defined_block {}.should == false
    KernelSpecs::BlockGiven.defined_block_inside_block {}.should == false
  end

  it "returns false outside of a method" do
    block_given?.should == false
  end
end

describe "Kernel.block_given?" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:block_given?)
  end
end
