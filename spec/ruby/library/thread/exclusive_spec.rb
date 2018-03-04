require_relative '../../spec_helper'
require 'thread'

describe "Thread.exclusive" do
  before :each do
    ScratchPad.clear
  end

  it "returns the result of yielding" do
    Thread.exclusive { :result }.should == :result
  end
end
