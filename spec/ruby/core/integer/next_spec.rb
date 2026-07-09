require_relative '../../spec_helper'

describe "Integer#next" do
  it "is an alias of Integer#succ" do
    Integer.instance_method(:next).should == Integer.instance_method(:succ)
  end
end
