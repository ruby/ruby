require_relative '../../spec_helper'

describe "Float#quo" do
  it "is an alias of Float#fdiv" do
    Float.instance_method(:quo).should == Float.instance_method(:fdiv)
  end
end
