require_relative '../../spec_helper'

describe "Float#===" do
  it "is an alias of Float#==" do
    Float.instance_method(:===).should == Float.instance_method(:==)
  end
end
