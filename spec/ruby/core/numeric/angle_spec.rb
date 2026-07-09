require_relative '../../spec_helper'

describe "Numeric#angle" do
  it "is an alias of Numeric#arg" do
    Numeric.instance_method(:angle).should == Numeric.instance_method(:arg)
  end
end
