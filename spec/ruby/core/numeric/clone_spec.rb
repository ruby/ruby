require_relative '../../spec_helper'

describe "Numeric#clone" do
  it "returns self" do
    value = 1
    value.clone.should equal(value)

    subclass = Class.new(Numeric)
    value = subclass.new
    value.clone.should equal(value)
  end

  it "does not change frozen status" do
    1.clone.frozen?.should == true
  end

  it "accepts optonal keyword argument :freeze" do
    value = 1
    value.clone(freeze: true).should equal(value)
  end

  it "raises ArgumentError if passed freeze: false" do
    -> { 1.clone(freeze: false) }.should raise_error(ArgumentError, /can't unfreeze/)
  end
end
