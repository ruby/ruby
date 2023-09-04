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

  it "accepts optional keyword argument :freeze" do
    value = 1
    value.clone(freeze: true).should equal(value)
  end

  it "raises ArgumentError if passed freeze: false" do
    -> { 1.clone(freeze: false) }.should raise_error(ArgumentError, /can't unfreeze/)
  end

  it "does not change frozen status if passed freeze: nil" do
    value = 1
    value.clone(freeze: nil).should equal(value)
  end
end
