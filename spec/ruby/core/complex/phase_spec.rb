require_relative '../../spec_helper'

describe "Complex#phase" do
  it "is an alias of Complex#arg" do
    Complex.instance_method(:phase).should == Complex.instance_method(:arg)
  end
end
