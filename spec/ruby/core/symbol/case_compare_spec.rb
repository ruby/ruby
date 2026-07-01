require_relative '../../spec_helper'

describe "Symbol#===" do
  it "is an alias of Symbol#==" do
    Symbol.instance_method(:===).should == Symbol.instance_method(:==)
  end
end
