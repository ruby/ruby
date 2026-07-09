require_relative '../../spec_helper'

describe "Float#inspect" do
  it "is an alias of Float#to_s" do
    Float.instance_method(:inspect).should == Float.instance_method(:to_s)
  end
end
