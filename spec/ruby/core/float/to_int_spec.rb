require_relative '../../spec_helper'

describe "Float#to_int" do
  it "is an alias of Float#to_i" do
    Float.instance_method(:to_int).should == Float.instance_method(:to_i)
  end
end
