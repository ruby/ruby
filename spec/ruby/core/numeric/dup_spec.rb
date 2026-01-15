require_relative '../../spec_helper'

describe "Numeric#dup" do
  it "returns self" do
    value = 1
    value.dup.should equal(value)

    subclass = Class.new(Numeric)
    value = subclass.new
    value.dup.should equal(value)
  end

  it "does not change frozen status" do
    1.dup.frozen?.should == true
  end
end
