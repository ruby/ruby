require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

describe Object, "#bignum_value" do
  it "returns a value that is an instance of Bignum on any platform" do
    bignum_value.should ==  0x8000_0000_0000_0000
  end

  it "returns the default value incremented by the argument" do
    bignum_value(42).should == 0x8000_0000_0000_002a
  end
end

describe Object, "#nan_value" do
  it "returns NaN" do
    nan_value.nan?.should be_true
  end
end

describe Object, "#infinity_value" do
  it "returns Infinity" do
    infinity_value.infinite?.should == 1
  end
end
