require_relative '../../spec_helper'

describe "String#===" do
  it "is an alias of String#==" do
    String.instance_method(:===).should == String.instance_method(:==)
  end
end
