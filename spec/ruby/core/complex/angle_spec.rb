require_relative '../../spec_helper'

describe "Complex#angle" do
  it "is an alias of Complex#arg" do
    Complex.instance_method(:angle).should == Complex.instance_method(:arg)
  end
end
