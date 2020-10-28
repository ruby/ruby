require_relative '../../spec_helper'

describe "Float#finite?" do
  it "returns true for finite values" do
    3.14159.should.finite?
  end

  it "returns false for positive infinity" do
    infinity_value.should_not.finite?
  end

  it "returns false for negative infinity" do
    (-infinity_value).should_not.finite?
  end

  it "returns false for NaN" do
    nan_value.should_not.finite?
  end
end
