require_relative '../../spec_helper'

describe "Float#angle" do
  it "is an alias of Float#arg" do
    Float.instance_method(:angle).should == Float.instance_method(:arg)
  end
end
