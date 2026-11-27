require_relative '../../spec_helper'

describe "Float#arg" do
  it "returns NaN if NaN" do
    f = nan_value
    f.arg.nan?.should == true
  end

  it "returns self if NaN" do
    f = nan_value
    f.arg.should.equal?(f)
  end

  it "returns 0 if positive" do
    1.0.arg.should == 0
  end

  it "returns 0 if +0.0" do
    0.0.arg.should == 0
  end

  it "returns 0 if +Infinity" do
    infinity_value.arg.should == 0
  end

  it "returns Pi if negative" do
    (-1.0).arg.should == Math::PI
  end

  # This was established in r23960
  it "returns Pi if -0.0" do
    (-0.0).arg.should == Math::PI
  end

  it "returns Pi if -Infinity" do
    (-infinity_value).arg.should == Math::PI
  end
end
