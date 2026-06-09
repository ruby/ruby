require_relative '../../spec_helper'

describe "Module#inspect" do
  it "is an alias of Module#to_s" do
    Module.instance_method(:inspect).should == Module.instance_method(:to_s)
  end
end
