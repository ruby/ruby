require_relative '../../spec_helper'

describe "Integer#===" do
  it "is an alias of Integer#==" do
    Integer.instance_method(:===).should == Integer.instance_method(:==)
  end
end
