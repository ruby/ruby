require_relative '../../spec_helper'

describe "Array#prepend" do
  it "is an alias of Array#unshift" do
    Array.instance_method(:prepend).should == Array.instance_method(:unshift)
  end
end
