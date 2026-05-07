require_relative '../../spec_helper'

describe "Float#eql?" do
  it "returns true if other is a Float equal to self" do
    0.0.eql?(0.0).should == true
  end

  it "returns false if other is a Float not equal to self" do
    1.0.eql?(1.1).should == false
  end

  it "returns false if other is not a Float" do
    1.0.eql?(1).should == false
    1.0.eql?(:one).should == false
  end
end
