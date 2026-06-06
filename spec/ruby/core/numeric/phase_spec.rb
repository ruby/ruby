require_relative '../../spec_helper'

describe "Numeric#phase" do
  it "is an alias of Numeric#arg" do
    Numeric.instance_method(:phase).should == Numeric.instance_method(:arg)
  end
end
