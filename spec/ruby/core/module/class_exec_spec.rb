require_relative '../../spec_helper'

describe "Module#class_exec" do
  it "is an alias of Module#module_exec" do
    Module.instance_method(:class_exec).should == Module.instance_method(:module_exec)
  end
end
