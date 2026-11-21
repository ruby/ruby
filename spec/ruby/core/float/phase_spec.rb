require_relative '../../spec_helper'

describe "Float#phase" do
  it "is an alias of Float#arg" do
    Float.instance_method(:phase).should == Float.instance_method(:arg)
  end
end
