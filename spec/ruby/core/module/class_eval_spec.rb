require_relative '../../spec_helper'

describe "Module#class_eval" do
  it "is an alias of Module#module_eval" do
    Module.instance_method(:class_eval).should == Module.instance_method(:module_eval)
  end
end
