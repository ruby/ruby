require_relative '../../spec_helper'

describe "Method#===" do
  it "is an alias of Method#call" do
    Method.instance_method(:===).should == Method.instance_method(:call)
  end
end
